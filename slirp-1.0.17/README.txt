Slirp is a TCP/IP emulator which turns an ordinary shell account
into a (C)SLIP/PPP account.  This is used by AppPot/UML to provide
network connectivity for UML VMs, using only userspace components.

Slirp was written by Danny Gasparovski.
Copyright (c), 1995,1996 All Rights Reserved.

See file `COPYRIGHT` for the software licence terms and conditions.

Slirp is included in the AppPot source repository as a convenience to
users of AppPot, as is apparently unmaintanted upstream as of 2012.
Only Debian/Ubuntu still ship the source and build the package; the
current Debian maintainer of the `slirp` package is Roberto Lumbreras
<rover@debian.org>.  The files here have been imported from the
Debian package, and I'll try to keep them in sync as much as possible.


## Installing Slirp

When installing Slirp for use with AppPot, you only need the "full
bolt" executable (i.e., without slowing down data transfer to match
modem speed).

1. Run the following commands in order to compile the binary `slirp-fullbolt`:

        cd src
        export CFLAGS="-DFULL_BOLT -O2 -I. -DUSE_PPP -DUSE_MS_DNS -fno-strict-aliasing -Wno-unused"
        make CFLAGS="$CFLAGS" PPPCFLAGS="$CFLAGS" clean all

2. To install, just copy the `src/slirp` file to a binary directory:

        sudo cp -a slirp /usr/local/bin/slirp-fullbolt


## References

* Slirp homepage: http://slirp.sourceforge.net/
* AppPot: http://apppot.googlecode.com/
* UML (User-Mode Linux): http://user-mode-linux.sourceforge.net/
