#! /bin/sh
#
PROG="$(basename $0)"

usage () {
cat <<EOF
Usage:
  $PROG base
  $PROG changes [FILE]
  $PROG merge [FILE]

The function performed by this script depends on the action word that
begins its invocation:

  base      Record the current system state; subsequent 'changes'
            invocations produce an archive file with the differences
            from the last recorded base state.

  changes   Make an archive file at FILE containing the differences from
            the last snapshot created with '$PROG base'.  
            If FILE is omitted, defaults to '/var/lib/apppot/snapshot.tgz'

  merge     Merge differences from a the archive file at FILE
            into the current system.
            If FILE is omitted, defaults to '/var/lib/apppot/snapshot.tgz'


Options:

  -v, --verbose     Verbosely print what files are being saved/restored.

  -n, --just-print  Do not make any modification to the system;
                    just print what would have been done.

  -h, --help        Print this help text.

EOF
}


## defaults

base_snap_file='/var/lib/apppot/base.snap'
exclude_file='/var/lib/apppot/apppot-snap.exclude'


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

maybe=''
verbose=''

if [ "x$(getopt -T)" == 'x--' ]; then
    # old-style getopt, use compatibility syntax
    set -- $(getopt 'hnv' "$@")
else
    # GNU getopt
    eval set -- $(getopt --shell sh -l 'just-print,help,no-act,verbose' -o 'hnv' -- "$@")
fi
while [ $# -gt 0 ]; do
    case "$1" in
        --just-print|--no-act|-n) maybe='echo' ;;
        --help|-h) usage; exit 0 ;;
        --verbose|-v) verbose='-v' ;;
        --) shift; break ;;
    esac
    shift
done

action=$1

## main

require_command tar
require_command mktemp

if ! [ -d $(dirname "$base_snap_file") ]; then
    die 1 "Directory '$(dirname "$base_snap_file")' that should host snapshot files, is non-existent."
fi

if ! [ -r "$exclude_file" ]; then
    die 1 "Exclude file '$exclude_file' cannot be read."
fi

case $action in

    base) 
        tar $verbose --create -f /dev/null -C / . \
            --listed-incremental="$base_snap_file" \
            --exclude-from="$exclude_file" --exclude-backups \
            --anchored --wildcards-match-slash
        ;;

    changes) 
        archive="${2:-/var/lib/apppot/snapshot.tgz}"
        # create a temporary copy of the tar snapfile, as tar modifies
        # it during a `--create` operation
        snapfile=`mktemp` \
            || die 1 "Cannot create temporary snapshot file."
        trap "{ rm -f '$snapfile'; }" EXIT
        $maybe cp $verbose "$base_snap_file" "$snapfile" \
            || die 1 "Cannot copy snapshot file to temporary location '$snapfile'."
        $maybe tar $verbose --create --auto-compress -f "$archive" -C / . \
            --listed-incremental="$snapfile" \
            --one-file-system \
            --exclude-from="$exclude_file" --exclude-backups \
            --exclude="$snapfile" --exclude="$archive" --exclude="$exclude_file" \
            --anchored --wildcards-match-slash
        ;;

    merge) 
        archive="${2:-/var/lib/apppot/snapshot.tgz}"
        $maybe tar $verbose --extract --auto-compress -f "$archive" -C / \
            --same-owner --same-permissions \
            --listed-incremental="$base_snap_file" \
            --exclude-from="$exclude_file" --exclude-backups \
            --exclude="$snapfile" --exclude="$archive" --exclude="$exclude_file" \
            --anchored --wildcards-match-slash
        ;;
esac