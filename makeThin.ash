#!/usr/bin/env ash
#-------------------------------------------------------------------------
#   Copyright (C) 2010, 2011 Ruben Miguelez Garcia
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, version 3.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#-------------------------------------------------------------------------
#
# The documentation of this program can be found on http://vmutils.blogspot.com/
#
# To start using this script, place this file on an ESX and run
# . /path/<name_of_this_file>
#
#
# v1 All basic functionality working perfectly
# v2 Improved code to extract the vmdks from the vmx instead of just try all vmdks
# v3 Improved code of cleanup to not ask when there is nothing to delete
# v4 Added functionality to pass as a parameter datastores to ignore during the checks (if desired)
# v5 Reduced complexity of entire program, as clonning never touches the CID and therefore there is no need to look for other vmdks pointing to the one we will convert.
# v5 Added functions to convert disks alone, find them and do both (find+convert)
# v5 Added checks agains RDMs
# v6 Cleaned up unnecessary functions and added computeThin
#
# Every time a pipe is used the second process may be executed in a subshell. If so, the keyboard redirection does not work
# For that reason some of these functions can not be used in other scripts.
#
#==== Auxiliary Functions ====================================================
SizeH () { ls -lh "$1" | awk  '{ print  $5   }'; }
#------------------
isThin () { result=`grep -i thinProvisioned "$1"` ; if [ "$result" = 'ddb.thinProvisioned = "1"' ] ; then echo yes; else echo no; fi; }
#------------------
isBaseDisk () {
# Ensure that the disk is both, base disk (no snapshot) and a virtual disk (not an RDM)
result=`grep -i parentCID "$1"`;
result2=`grep -i createType "$1"`;
if [ "$result" = "parentCID=ffffffff"  -a  "$result2" = 'createType="vmfs"' ] ; then echo "yes"; else echo "no"; fi; }
#============= cleanupSAFETMP =================================================
cleanupSAFETMP () {
# Usage: cleanupSAFETMP /path/
# Find SAFETMP*vmdk files recursively under the path specified and ask you for confirmation before deleting them.

# If no argument provided, then look where we are
if [ "$1" != "" ]; then LOCATION="$*"; else LOCATION="."; fi;

# Check if there is something to clean up.
RESULTLOOKINGTARGETS=`find $LOCATION -name "SAFETMP*vmdk"`;
# Decide
if [ "$RESULTLOOKINGTARGETS" = "" ] ; then
    printf "\nNo SAFETMP*vmdk files found under the specified location (default is \".\"). Nothing to clean up. Exiting.\n\n";
else
    printf "\n\tFiles found:\n";
    echo "$RESULTLOOKINGTARGETS";
    printf "\nDo you want to delete these files?\n\n";
    ANSWER="0";
    printf "Answer (y/n): ";
    read ANSWER;
    if [ "$ANSWER" = "Y" -o "$ANSWER" = "y" ] ; then
        find $LOCATION -name "SAFETMP*vmdk" ! -name "*-flat.vmdk" ! -name "*-delta.vmdk" | while read TODELETE ; do
        vmkfstools -U  "$TODELETE" ; done;
        printf "\nDone.\n\n";
    else
        printf "\nNothing deleted.\n\n";
    fi;
fi;
}
#============ findBaseDisks ======================================================
findBaseDisks () {
# Easy query to find vmdks that have a -flat.vmdk and are supposed to be BaseDisks.
# Snapshots have a -delta.vmdk supporting the data instead.
# This only finds Base Disks that have BOTH files, file.vmdk and its file-flat.vmdk

# Get original location
ORIGINALLOCATION=`pwd`;

# If no argument provided, then look where we are
if [ "$1" != "" ]; then
    LOCATION="$*";
else
    LOCATION=".";
fi;

# Find the -flat.vmdk files and from them the .vmdk and display if it exists.
find $LOCATION -iname "*-flat.vmdk" | while read DISKPATH; do
    DPATH=`dirname  "$DISKPATH"`;
    DNAME=`basename "$DISKPATH" "-flat.vmdk"`;
    if [ -e "$DPATH/$DNAME.vmdk" ]; then echo "$DPATH/$DNAME.vmdk"; fi;
done; }
#============= findAndMakeDiskThin = makeThin ======================================
alias makeThin=findAndMakeDiskThin ;
findAndMakeDiskThin () {
# Usage: findAndMakeDiskThin  /path/
# It will find Base Disks recursively under the path specified and one by one, convert them to thin provision ONLY if required and ONLY if you confirm the operation.
# To say YES you just need to press y or Y, without Enter.
# Any other key, including Enter will mean NO.


    { # Another pair of keys to allow keyboard redirection

    # Get original location
    ORIGINALLOCATION=`pwd`;

    # If no argument provided, then look where we are
    if [ "$1" != "" ]; then
        LOCATION="$*";
    else
        LOCATION=".";
    fi;

    findBaseDisks "$LOCATION" | while read VDISK ; do

    # Check it exists
    if [ ! -e "$VDISK" ]; then echo "$VDISK file not found."; else
    printf "\n-----------------------------------------------------------------------------\n\n"

    # Check that the disk is thin before continuing
    if [ "`isThin \"$VDISK\"`" = "yes" ]; then echo "$VDISK is thinProvisioned, skipping." ; else

    # Check that the disk is a Base Disk (not snapshot/RDM) before continuing
    if [ "`isBaseDisk \"$VDISK\"`" = "no" ]; then echo "$VDISK is a snapshot and/or an RDM, skipping." ; else

    # Display its size and free space on Datastore
    DPATH=`dirname  "$VDISK"`;
    DNAME=`basename "$VDISK" ".vmdk"`;
    DNAMEFLAT="$DNAME-flat.vmdk";
    printf "\nWorking with $VDISK. Maximum space needed: "; SizeH "$DPATH/$DNAMEFLAT"; echo "";
    vdf -h "$DPATH";

    # Ask for confirmation
    printf "\n-- Convert to thin? (y/n): "; INPUT="0"; read INPUT <&6;  if [ "$INPUT" = "Y" -o "$INPUT" = "y" ] ; then
        echo ""; #echo -e "yes do it\n" ;

        # Rename source
        echo "Will run: vmkfstools -E \"$VDISK\" \"$DPATH/SAFETMP$DNAME.vmdk\""
        vmkfstools -E "$VDISK" "$DPATH/SAFETMP$DNAME.vmdk"

        # Clone to thin
        echo "Will run: vmkfstools -i  \"$DPATH/SAFETMP$DNAME.vmdk\" -d thin  \"$VDISK\""
        vmkfstools -i  "$DPATH/SAFETMP$DNAME.vmdk" -d thin  "$VDISK"

        # Verify
        printf "\n Visual verification\n"
        ls -l "$DPATH/SAFETMP$DNAME.vmdk" "$DPATH/SAFETMP$DNAME-flat.vmdk" "$DPATH/$DNAME.vmdk" "$DPATH/$DNAME-flat.vmdk"
    else
        #echo "DON'T do it" ;
        echo ""
    fi;    # Confirmation to convert

    fi; # is BaseDisk
    fi; # isThin
    fi; # file exist

    done;

} 6>&0   # for redirection of keyboard
echo "";
};
#============ computeThin =================================================
computeThin () {
# Usage: computeThin  /path/
# Using the linux command 'du' it will calculate the difference between real size and apparent size in terms of blocks used.
# The comparison is valid once the file is thin provision, otherwise both results are the same.

LOCATION=$1;
(echo "Thin Thick File"; find "$LOCATION"  -name "*-flat.vmdk" | while read DISK; do du -h "$DISK" | awk '{print $1}'; du -h --apparent-size "$DISK" ; done ) | column -t;
echo "";
(echo -n "Thin:  " ; find "$LOCATION" -name "*-flat.vmdk" -print0 | xargs -0 du -h -c | tail -1 ;  echo -n "Thick: " ; find "$LOCATION" -name "*-flat.vmdk" -print0 | xargs -0 du -h --apparent-size -c | tail -1 ) | column -t;
}

#=============================================================================
