#! /bin/sh
#
# Start an AppPot system image to execute a given program with
# specified arguments.
#
# Author: Riccardo Murri <riccardo.murri@gmail.com>
#
#
# Copyright (C) 2009-2012 GC3, University of Zurich. All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#
PROG="$(basename $0)"
VERSION='(SVN $Revision$)'

usage () {
cat <<EOF
Usage: $PROG [options] [PROG ARGS...]

Start an AppPot system image to execute PROG with the given ARGS.
If PROG and ARGS are omitted, then start the AppPot system image
with an interactive console.

If a valid MPI host file is found, connect interface 'eth1' in the
AppPot system image to the local multicast address 239.255.82.77 on
port 8277.

The following options are recognized; option processing stops at the
first non-option argument (which must be PROG):

  --apppot PATH   Use the specified AppPot system image.
                  You can also specify a pair COWFILE:IMAGEFILE,
                  in which case IMAGEFILE will be opened read-only
                  and all changes will be written to COWFILE instead.
                  
  --changes FILE  Merge the specified changes file into the AppPot system 
                  image.  FILE must have been created with the 
                  'apppot-snap changes' command (which see).
                  
  --mem NUM       Amount of memory to allocate to the
                  AppPot system image; use the 'M' or 'G'
                  suffix to denote MB or GB respectively.
                  
  --slirp PATH    Use the executable found at PATH as
                  the 'slirp' command for providing
                  IP network access.
                  
  --uml PATH      Use the UML 'linux' executable found at PATH.
                  
  --id NAME       Use NAME to control the running instance 
                  with 'uml_mconsole'.

  --extra ARG     Append ARG to the UML kernel command-line.
                  (Repeat option multiple times to append more ARGs)

  --version, -V   Print version and exit.

  --help, -h      Print this help text.

EOF
}


## helper functions
die () {
  rc="$1"
  shift
  (echo -n "$PROG: ERROR: ";
      if [ $# -gt 0 ]; then echo "$@"; else cat; fi) 1>&2
  exit $rc
}

warn () {
  (echo -n "$PROG: WARNING: ";
      if [ $# -gt 0 ]; then echo "$@"; else cat; fi) 1>&2
}

have_command () {
  type "$1" >/dev/null 2>/dev/null
}

link_target () {
  find "$1" -printf '%l'
}

quote () {
    echo "$1" | sed -e 's|\\|\\\\|g;s|"|\\"|g;'
}

require_command () {
  if ! have_command "$1"; then
    die 1 "Could not find required command '$1' in system PATH. Aborting."
  fi
}

stdin_is_not_dev_null () {
  test "$(link_target /proc/self/fd/0)" != '/dev/null'
}

is_absolute_path () {
    expr match "$1" '/' >/dev/null 2>/dev/null
}


## parse command-line 

# defaults
if [ -n "$APPPOT_IMAGE" ]; then
    apppot="$APPPOT_IMAGE"
else
    apppot="apppot.img"
fi

if [ -n "$APPPOT_MEM" ]; then
    mem="$APPPOT_MEM"
else
    mem="512M"
fi

extra=''

# try to provide sensible defaults
if [ -x "`pwd`/slirp" ]; then
    slirp="`pwd`/slirp"
elif have_command slirp-fullbolt; then
    slirp='slirp-fullbolt'
elif have_command slirp; then
    slirp='slirp'
else
    slirp=''
fi

if [ -x "`pwd`/linux" ]; then
    linux="`pwd`/linux"
elif [ -n "$APPPOT_KERNEL" ]; then
    linux="$APPPOT_KERNEL"
elif have_command linux; then
    linux="linux"
else
    linux=''
fi

# parse command line
while [ $# -gt 0 ]; do
    case "$1" in
        --apppot) shift; apppot="$1" ;;
        --changes|--merge) shift; changes="$1" ;;
        --extra|-X) shift; extra="$extra $1" ;;
        --id|--umid) shift; umid="$1" ;;
        --mem) shift; mem="$1" ;;
        --slirp) shift; slirp="$1" ;;
        --linux|--kernel|--uml) shift; linux="$1" ;;
        --help|-h) usage; exit 0 ;;
        --version|-V) echo "$PROG $VERSION"; exit 0 ;;
        --*) die 1 "Unknown option '$1'; type '$PROG --help' to see usage help." ;;
        --) shift; break ;;
        # parsing stops at the first non-option argument
        *) break ;;
    esac
    shift
done


## main

# parse the `--apppot` argument and check for existence of the backing file
case "$apppot" in
    # UMLx allows both `ubdX=cow,back` and `ubdX=cow:back`
    *,*)
        apppot_cow="$(echo "$apppot" | cut -d, -f1)"
        apppot_img="$(echo "$apppot" | cut -d, -f2)"
        ;;
    *:*)
        apppot_cow="$(echo "$apppot" | cut -d: -f1)"
        apppot_img="$(echo "$apppot" | cut -d: -f2)"
        ;;
    # else there's a single file, which is opened R/W
    *)
        apppot_cow=''
        apppot_img="$apppot"
        ;;
esac
if ! [ -r "$apppot_img" ]; then 
    die 1 "Cannot read AppPot image file '$apppot_img' - aborting."
fi
if [ -z "$apppot_cow" ] && [ ! -w "$apppot_img" ]; then
    apppot_cow="apppot.$(hostname).$$.cow"
    warn "AppPot image file '$apppot_img' is read-only: writing changes to COW file '$appot_cow'."
    apppot="$apppot_cow:$apppot_img"
fi


if [ -z "$linux" ]; then
    die 1 "No 'linux' executable detected, please specify the UML kernel via the '--linux' option."
else
    require_command $linux
fi

if [ -z "$slirp" ]; then
    warn "No 'slirp' or 'slirp-fullbolt' executable detected, disabling network access."
else
    require_command $slirp
    opt_slirp="eth0=slirp,,$slirp"
fi

if [ -z "$umid" ]; then
    umid=apppot."$(hostname).$$"
fi

if [ -n "$changes" ]; then
    if ! is_absolute_path "$changes"; then
        changes="$(pwd)/${changes}"
    fi
    opt_changes="apppot.changes=${changes}"
fi

# determine whether $apppot is a filesystem or disk image, 
# and generate a `root=...` kernel parameter
# XXX: complicated heuristics, may fail unpredictably
require_command expr
require_command file
what=$(file --dereference --brief "$apppot_img")
case "$what" in
    'x86 boot sector'*)
        # disk image, determine boot partition
        bootpart=$(/usr/bin/expr match "$what" '.*partition \([1-4]\): ID=0x83, active')
        if [ -n "$bootpart" ]; then
            rootfs="/dev/ubda$bootpart"
        else
            warn "Disk image '$apppot_img' contains no bootable partition, assuming Linux is on partition 1."
            rootfs="/dev/ubda1"
        fi
        ;;
    *'filesystem data'*)
        # filesystem image
        rootfs=/dev/ubda
        ;;
esac
            


# gather environmental information
require_command id
APPPOT_UID=`id -u`
APPPOT_GID=`id -g`

if [ -n "$TERM" ]; then
    opt_term="TERM=$TERM"
fi

# prepare command-line invocation
cmdline=''
for arg in "$@"; do
    cmdline="$cmdline '$(quote $arg)'"
done

# UMLx cannot use stdin for console input if it is connected to a file
# or other no-wait stream (e.g., /dev/null); in order to make sure
# that this startup script can run with STDIN connected to any stream,
if test -t 0; then 
    # STDIN is a terminal, start UMLx as usual
    $linux \
        umid="$umid" \
        highres=off \
        mem="$mem" \
        hostfs=/ \
        ubd0="$apppot" \
        "$opt_slirp" \
        eth1=mcast,,239.255.82.77,8277,1 \
        con=fd:0,fd:1 \
        root="$rootfs" \
        "$opt_term" \
        "$opt_changes" \
        $extra \
        apppot.uid=$APPPOT_UID \
        apppot.gid=$APPPOT_GID \
        apppot.jobdir=`pwd` \
        -- "$cmdline"

# STDIN is not a terminal; what we can do now depends on the
# availability of the `empty` helper command.
#
# See http://empty.sourceforge.net/ or install Debian/Ubuntu package
# 'empty-expect'.
#

elif have_command empty && stdin_is_not_dev_null; then
    # save STDIN for later use with `empty -s`
    exec 3<&0
    
    # detach from the input stream
    exec < /dev/null
    
    # start UMLx
    empty -f -i .apppot.stdin -o .apppot.stdout $linux \
        umid="$umid" \
        mem="$mem" \
        hostfs=/ \
        ubd0="$apppot" \
        "$opt_slirp" \
        eth1=mcast,,239.255.82.77,8277,1 \
        con=fd:0,fd:1 \
        root="$rootfs" \
        "$opt_term" \
        "$opt_changes" \
        $extra \
        apppot.uid=$APPPOT_UID \
        apppot.gid=$APPPOT_GID \
        apppot.jobdir=`pwd` \
        -- "$cmdline"
    
    # send original STDIN to the UMLx through the named pipe
    (empty -s -o .apppot.stdin -c 0<&3) &
    
    # send UMLx console output to STDOUT
    cat .apppot.stdout


else
    require_command kill
    require_command mkfifo
    require_command sleep

    # No helper programs, we use the following trick: 
    #   - create a named FIFO
    #   - connect a process that writes no output to the write end of the FIFO 
    #   - connect the UMLx instance to the read end of the FIFO,
    #     and use STDIN/STDOUT for the system console
    #
    mkfifo .apppot.stdin \
        || die 1 "Cannot create FIFO '`pwd`/.apppot.stdin'"
    (sleep 365d) > .apppot.stdin &
    stdin_pid=$!
    
    # ensure the FIFO is removed and the `sleep` process is killed
    cleanup () {
        kill $stdin_pid
        rm -f .apppot.stdin
    }
    trap "cleanup" EXIT
    
    # I found no way of conveying arbitrary STDIN content into the
    # named FIFO; so this trick only works for simulating a null
    # STDIN, so let's warn users.
    #
    if stdin_is_not_dev_null; then
        warn "Redirecting output from /dev/null, any content to STDIN will be lost."
    fi
    
    # start UMLx with input from the FIFO
    $linux \
        umid="$umid" \
        mem="$mem" \
        hostfs=/ \
        ubd0="$apppot" \
        "$opt_slirp" \
        eth1=mcast,,239.255.82.77,8277,1 \
        con=fd:0,fd:1 \
        root="$rootfs" \
        "$opt_term" \
        "$opt_changes" \
        $extra \
        apppot.uid=$APPPOT_UID \
        apppot.gid=$APPPOT_GID \
        apppot.jobdir=`pwd` \
        -- "$cmdline" \
        < .apppot.stdin
fi
