#! /bin/sh
#
PROG="$(basename $0)"

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

  --mem NUM      Amount of memory to allocate to the
                 AppPot system image; use the 'M' or 'G'
                 suffix to denote MB or GB respectively.

  --slirp PATH   Use the executable found at PATH as
                 the 'slirp' command for providing
                 IP network access.

  --apppot PATH  Use the specified AppPot system image.

  --uml PATH     Use the UML 'linux' executable found at PATH.

  --help, -h     Print this help text.

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

have_command () {
  type "$1" >/dev/null 2>/dev/null
}

require_command () {
  if ! have_command "$1"; then
    die 1 "Could not find required command '$1' in system PATH. Aborting."
  fi
}

is_absolute_path () {
    expr match "$1" '/' >/dev/null 2>/dev/null
}


## parse command-line 

# defaults
apppot="apppot.img"
mem="512M"
slirp="`pwd`/slirp"
linux="linux"

while [ $# -gt 0 ]; do
    case "$1" in
        --apppot) shift; apppot="$1" ;;
        --mem) shift; mem="$1" ;;
        --slirp) shift; slirp="$1" ;;
        --uml|--linux) shift; linux="$1" ;;
        --help|-h) usage; exit 0 ;;
        --*) die 1 "Unknown option '$1'; type '$PROG --help' to see usage help." ;;
        --) shift; break ;;
        *) break ;;
    esac
    shift
done


## main

require_command $linux
require_command $slirp

require_command id


# gather environmental information
APPPOT_UID=`id -u`
APPPOT_GID=`id -g`


# UMLx cannot use stdin for console input if it is connected to a file
# or other no-wait stream (e.g., /dev/null); in order to make sure
# that this startup script can run with STDIN connected to any stream,
if test - t 0; then 
    # STDIN is a terminal, start UMLx as usual
    $linux \
        mem="$mem" \
        hostfs=`pwd` \
        ubd0="$apppot" \
        eth0=slirp,,"$slirp" \
        eth1=mcast,,239.255.82.77,8277,1 \
        con=null con0=fd:0,fd:1 \
        root=/dev/ubda \
        apppot.uid=$APPPOT_UID \
        apppot.gid=$APPPOT_GID \
        apppot.jobdir=`pwd` \
        -- "$@"

# STDIN is not a terminal; what we can do now depends on the
# availability of the `empty` helper command.
#
# See http://empty.sourceforge.net/ or install Debian/Ubuntu package
# 'empty-expect'.
#
elif have_command empty; then
    # start UMLx
    empty -f -i .apppot.stdin -o .apppot.stdout $linux \
        mem="$mem" \
        hostfs=`pwd` \
        ubd0="$apppot" \
        eth0=slirp,,"$slirp" \
        eth1=mcast,,239.255.82.77,8277,1 \
        con=null con0=fd:0,fd:1 \
        root=/dev/ubda \
        apppot.uid=$APPPOT_UID \
        apppot.gid=$APPPOT_GID \
        apppot.jobdir=`pwd` \
        -- "$@"
    
    # save STDIN for later use with `empty -s`
    exec 3<&0
    
    # detach from the input stream
    exec < /dev/null
    
    # send original STDIN to the UMLx through the named pipe
    (empty -s -o .apppot.stdin 0<&3) &
    
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
    echo 1>&2 "$PROG: WARNING: Redirecting output from /dev/null, any content to STDIN will be lost."
    
    # start UMLx with input from the FIFO
    $linux \
        mem="$mem" \
        hostfs=`pwd` \
        ubd0="$apppot" \
        eth0=slirp,,"$slirp" \
        eth1=mcast,,239.255.82.77,8277,1 \
        con=null con0=fd:0,fd:1 \
        root=/dev/ubda \
        apppot.uid=$APPPOT_UID \
        apppot.gid=$APPPOT_GID \
        apppot.jobdir=`pwd` \
        -- "$@" \
        < .apppot.stdin
fi