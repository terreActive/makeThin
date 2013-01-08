makeThin
========

Find thick provisioned VMs and convert them to thin provisioned.

`makeThin.bash` is a copy of [the original](http://vmutils.t15.org/makeThin.Documentation/makeThin.Documentation.html#toc32) by Ruben Miguelez Garcia, while `makeThin.ash` is a conversion for use with ESXi. They should work exactly the same, except that 

1. the `ash` script doesn't check whether files are already in use. You therefore have to be extra careful to make sure the files are not in use by any other programs before running this script (commit c92deae733303dfc157efc836255bd2433d8a3e5), and
2. the `computeThin` command has been removed because BusyBox `du` doesn't support `--apparent-size`. You can still see the size difference in the vSphere Client after clicking Refresh Storage Usage.

Please refer to [the documentation](http://vmutils.t15.org/makeThin.Documentation/makeThin.Documentation.html) for further information.
