#! /bin/sh
#
PROG="$(basename $0)"
VERSION="0.16 (SVN $Revision$)"

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

  --apppot PATH  Use the specified AppPot system image.
                 You can also specify a pair COWFILE:IMAGEFILE,
                 in which case IMAGEFILE will be opened read-only
                 and all changes will be written to COWFILE instead.

  --mem NUM      Amount of memory to allocate to the
                 AppPot system image; use the 'M' or 'G'
                 suffix to denote MB or GB respectively.

  --slirp PATH   Use the executable found at PATH as
                 the 'slirp' command for providing
                 IP network access.

  --uml PATH     Use the UML 'linux' executable found at PATH.

  --id NAME      Use NAME to control the running instance 
                 with 'uml_mconsole'.

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

warn () {
  (echo -n "$PROG: WARNING: ";
      if [ $# -gt 0 ]; then echo "$@"; else cat; fi) 1>&2
}

have_command () {
  type "$1" >/dev/null 2>/dev/null
}

quote () {
    echo "$1" | sed -e 's|\\|\\\\|g;s|"|\\"|g;'
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
elif have_command linux; then
    linux="linux"
else
    linux=''
fi

# parse command line
while [ $# -gt 0 ]; do
    case "$1" in
        --apppot) shift; apppot="$1" ;;
        --id) shift; umid="$1" ;;
        --mem) shift; mem="$1" ;;
        --slirp) shift; slirp="$1" ;;
        --uml|--linux|--kernel) shift; linux="$1" ;;
        --help|-h) usage; exit 0 ;;
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
    if [ -z "$apppot_cow" ] && [ ! -w "$apppot_img" ]; then
        apppot_cow="apppot.$(hostname).$$.cow"
        warn "AppPot image file '$apppot_img' is read-only: writing changes to COW file '$appot_cow'."
        apppot="$apppot_cow:$apppot_img"
    fi
fi

if [ -z "$linux" ]; then
    die 1 "No 'linux' executable detected, please specify the UML kernel via the '--uml' option."
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


# gather environmental information
require_command id
APPPOT_UID=`id -u`
APPPOT_GID=`id -g`

if [ -n "$TERM" ]; then
    term="TERM=$TERM"
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
        root=/dev/ubda \
        $term \
        apppot.uid=$APPPOT_UID \
        apppot.gid=$APPPOT_GID \
        apppot.jobdir=`pwd` \
        -- "$cmdline"

# STDIN is not a terminal; what we can do now depends on the
# availability of the `empty` helper command.
#
# See http://empty.sourceforge.net/ or install Debian/Ubuntu package
# 'empty-expect'.
#f 
elif have_command empty; then
    # start UMLx
    empty -f -i .apppot.stdin -o .apppot.stdout $linux \
        umid="$umid" \
        mem="$mem" \
        hostfs=/ \
        ubd0="$apppot" \
        "$opt_slirp" \
        eth1=mcast,,239.255.82.77,8277,1 \
        con=fd:0,fd:1 \
        root=/dev/ubda \
        $term \
        apppot.uid=$APPPOT_UID \
        apppot.gid=$APPPOT_GID \
        apppot.jobdir=`pwd` \
        -- "$cmdline"
    
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
        umid="$umid" \
        mem="$mem" \
        hostfs=/ \
        ubd0="$apppot" \
        "$opt_slirp" \
        eth1=mcast,,239.255.82.77,8277,1 \
        con=fd:0,fd:1 \
        root=/dev/ubda \
        $term \
        apppot.uid=$APPPOT_UID \
        apppot.gid=$APPPOT_GID \
        apppot.jobdir=`pwd` \
        -- "$cmdline" \
        < .apppot.stdin
fi
