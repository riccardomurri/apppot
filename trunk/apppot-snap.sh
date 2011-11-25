#! /bin/sh
#
PROG="$(basename $0)"
VERSION='0.21 (SVN $Revision$)'

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
            If FILE is omitted, defaults to '$HOME/job/apppot.YYYY-MM-DD.changes.tar.gz'
            (if '$HOME/job' is a mountpoint for accessing the host filesystem)
            or, failing that, a file named 'apppot.changes.tar.gz' in the current
            directory.

  merge     Merge differences from a the archive file at FILE
            into the current system.
            If FILE is omitted, defaults to '$HOME/job/apppot.YYYY-MM-DD.changes.tar.gz'
            (if '$HOME/job' is a mountpoint for accessing the host filesystem)
            or, failing that, a file named 'apppot.changes.tar.gz' in the current
            directory.


Options:

  -v, --verbose     Verbosely print what files are being saved/restored.

  -n, --just-print  Do not make any modification to the system;
                    just print what would have been done.

  -h, --help        Print this help text.

EOF
}


## defaults

base_state_file='/var/lib/apppot/apppot-snap.base'
exclude_file='/var/lib/apppot/apppot-snap.exclude'


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

require_command () {
  if ! have_command "$1"; then
    die 1 "Could not find required command '$1' in system PATH. Aborting."
  fi
}

is_absolute_path () {
    expr match "$1" '/' >/dev/null 2>/dev/null
}

home_directory () {
    # if we're running under `sudo`, we want to use the real user's
    # $HOME, not `root`'s one...
    if [ -n "$SUDO_USER" ]; then
        echo $(getent passwd "$SUDO_USER" | cut -d: -f6)
    else
        echo $HOME
    fi
}

## parse command-line 

maybe=''
verbose=''

if [ "x$(getopt -T)" = 'x--' ]; then
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

require_command date
require_command tar
require_command mktemp
require_command mountpoint

if ! [ -d $(dirname "$base_state_file") ]; then
    die 1 "Directory '$(dirname "$base_state_file")' that should host snapshot files, is non-existent."
fi

if ! [ -r "$exclude_file" ]; then
    die 1 "Exclude file '$exclude_file' cannot be read."
fi

default_archive () {
# let the default archive location be what the init script expects
    home="$(home_directory)"
    if mountpoint -q "$home/job"; then
        echo "$home/job/apppot.$(date -I).changes.tar.gz"
    else
        echo "$(pwd)/apppot.changes.tar.gz"
        warn "Default archive location '$home/job' does not look like a hostfs mount, storing changes into '$default_archive' instead."
    fi
}

case $action in

    base) 
        if test -r "$base_state_file"; then
            warn "Deleting old base state file '$base_state_file', interrupting this command may leave the system without a valid base state."
            rm -f "$base_state_file"
        fi
        tar $verbose --create -f /dev/null -C / . \
            --listed-incremental="$base_state_file" \
            --exclude-from="$exclude_file" --exclude-backups \
            --anchored --wildcards-match-slash
        ;;

    changes) 
        archive="${2:-$(default_archive)}"
        # check that the snapfile exists and can be read
        test -r "$base_state_file" \
            || die 1 "Base state file '$base_state_file' does not exist."
        # create a temporary copy of the tar snapfile, as tar modifies
        # it during a `--create` operation
        snapfile=`mktemp` \
            || die 1 "Cannot create temporary state file."
        trap "{ rm -f '$snapfile'; }" EXIT
        $maybe cp $verbose "$base_state_file" "$snapfile" \
            || die 1 "Cannot copy base state file to temporary location '$snapfile'."
        $maybe tar $verbose --create --auto-compress -f "$archive" -C / . \
            --listed-incremental="$snapfile" \
            --one-file-system \
            --exclude-from="$exclude_file" --exclude-backups \
            --exclude="$snapfile" --exclude="$archive" --exclude="$exclude_file" \
            --anchored --wildcards-match-slash
        echo "Saved changes from base state into file '$archive'."
        ;;

    merge) 
        archive="${2:-$(default_archive)}"
        $maybe tar $verbose --extract --auto-compress -f "$archive" -C / \
            --same-owner --same-permissions \
            --listed-incremental="$base_state_file" \
            --exclude-from="$exclude_file" --exclude-backups \
            --exclude="$snapfile" --exclude="$archive" --exclude="$exclude_file" \
            --anchored --wildcards-match-slash
        ;;

    *)
        die 1 "Unknown action '$action'; type '$PROG --help' for usage help."
        ;;

esac