#! /bin/sh
#
# Sets up the the AppPot environment, including mounting
# hostfs directories, setting up MPI networking, etc.
# and then runs the job specified by users on the kernel
# command-line.  If no job is specified, starts SCREEN
# on the first console.
#
# Author: Riccardo Murri <riccardo.murri@gmail.com>
#
VERSION='(SVN $Revision$)'

# PATH should only include /usr/* if it runs after the mountnfs.sh script
PATH=/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin
NAME=apppot

echo "==== Starting AppPot $VERSION ..."

# Read configuration variable file if it is present
if [ -r /etc/default/$NAME ]; then
    . /etc/default/$NAME
fi


## defaults

APPPOT_USER=user
APPPOT_GROUP=users
APPPOT_HOME=/home/user


## auxiliary functions

# value EXPR
#
# Given an EXPR of the form `name=value`, output the `value` part.
#
value () {
    echo "$1" | cut -d= -f2-
}


# setup_apppot_user UID GID [USER GROUP]
#
# Create a user with the given UID and GID.  If given, arguments USER
# and GROUP specify the UNIX user name and primary group name; if
# omitted, they default to `user` (user name) and `users` (group
# name).
# 
setup_apppot_user () {
    # parse arguments
    uid=${1:?Missing required argument UID to setup_apppot_user}
    gid=${2:?Missing required argument GID to setup_apppot_user}
    user=${3:-user}
    group=${4:-users}

    echo "== Setting up AppPot user $user($uid) in group $group($gid) ..."

    # ensure GROUP exists with the given GID
    if getent group "$group" >/dev/null; then
        # group already exists, ensure given GID
        groupmod --gid "$gid" "$group"
    else
        # create user with given GID
        groupadd --gid "$gid" "$group"
    fi

    # ensure USER exists with the given UID/GID
    if getent passwd "$user" >/dev/null; then
        # user already exists, ensure given UID/GID
        usermod --uid "$uid" --gid "$gid" --shell /bin/sh "$user"
    else
        # create user with given UID/GID
        useradd --create-home --uid "$uid" --gid "$gid" --shell /bin/sh "$user"
    fi

    # ensure USER is authorized to sudo
    fgrep -q "$user" /etc/sudoers \
        || cat >> /etc/sudoers <<__EOF__

# user '$user' enabled by '$0'
$user  ALL=(ALL) NOPASSWD: ALL
__EOF__

    # define $APPPOT_HOME to the user home directory
    export APPPOT_HOME="`getent passwd "$user" | cut -d: -f6`"
    find "$APPPOT_HOME" -xdev -print0 | xargs --null chown "$uid":"$gid"

    # give $user access to the system console
    chown "$user" /dev/console

    # ensure that we can still use `screen` if UID/GID has changed from the default
    rm -rf /var/run/screen/S-$APPPOT_USER /var/run/screen/S-$user

    return 0
}


# mount_hostfs HOSTDIR MOUNTDIR
#
# Mount host directory HOSTDIR onto local mount point MOUNTDIR
#
mount_hostfs () { 
    hostdir=${1:?Missing required parameter HOSTDIR to 'mount_hostfs'}
    mountdir=${2:?Missing required parameter MOUNTDIR to 'mount_hostfs'}

    if fgrep -q hostfs /proc/filesystems; then
        echo "== Mounting host directory '$hostdir' on local directory '$mountdir' ..."
        mkdir -p "$mountdir"
        mount -t hostfs -o "$hostdir" host "$mountdir"
    else
        echo "== WARNING: No 'hostfs' support in this kernel, cannot mount '$hostdir' on '$mountdir' ..."
        return 1
    fi
}


# merge_changes FILE
#
# Merge the changes from FILE (path in the host filesystem).
# The named FILE must have been created by 'apppot-snap changes FILE'.
#
merge_changes () {
    changes_file="${1:?Missing required parameter FILE to 'merge_changes'}"

    echo "== Merging changes from host file '$changes_file' ..."
    mount -t hostfs -o / hostroot /mnt
    if [ ! -r "/mnt/$changes_file" ]; then
        warn "Cannot read changes file '$changes_file': not merging changes."
        return 1
    fi
    apppot-snap merge "/mnt/$changes_file"
    rc=$?
    umount /mnt
    return $rc
}


# setup_term TERM [DEFAULT]
#
# Set the `TERM` environment variable to the given value,
# or fall back to the DEFAULT if the specified
# terminal is not supported on this system.
# 
# If DEFAULT is omitted, use 'vt100'.
#
setup_term () {
    term="${1:?Missing required parameter TERM to 'setup_term'}"
    default_term="${2:-vt100}"

    term_name=`tput -T"$term" longname`
    if [ -z "$term_name" ]; then
        # terminal not supported, fall back to default
        echo "== WARNING: Terminal '$term' not supported, falling back to '$default_term'."
        export TERM="$default_term"
    else
        echo "== Using terminal $name"
        export TERM="$term"
    fi
}


## main

# Set the command line arguments to this shell from
# the ones that were passed to the kernel at boot.
# Return 1 if the `/proc/cmdline` file is not accessible.
#
# In addition, the following parameters are parsed
# and set as environment variables:
#   - `apppot.user`: sets variable APPPOT_USER
#   - `apppot.uid`: sets variable APPPOT_UID
#   - `apppot.group`: sets variable APPPOT_GROUP
#   - `apppot.gid`: sets variable APPPOT_GID
#   - `apppot.jobdir`: sets variable APPPOT_JOBDIR
#   - `apppot.tmpdir`: sets variable APPPOT_TMPDIR
#
if [ -r /proc/cmdline ]; then
    set -- `cat /proc/cmdline`
    while [ $# -gt 0 ]; do
        case "$1" in
            apppot.changes=*) export APPPOT_CHANGESFILE="$(value "$1")" ;;
            apppot.user=*)    export APPPOT_USER="$(value "$1")" ;;
            apppot.uid=*)     export APPPOT_UID="$(value "$1")" ;;
            apppot.group=*)   export APPPOT_GROUP="$(value "$1")" ;;
            apppot.gid=*)     export APPPOT_GID="$(value "$1")" ;;
            apppot.jobdir=*)  export APPPOT_JOBDIR="$(value "$1")" ;;
            apppot.tmpdir=*)  export APPPOT_TMPDIR="$(value "$1")" ;;
            TERM=*)           setup_term "$(value "$1")" ;;
        # `--` means end of kernel params and start of job arguments
            --) shift; break ;;
        esac
        shift
    done
fi

# mount job and scratch directories, if present
[ -n "$APPPOT_JOBDIR" ] && mount_hostfs $APPPOT_JOBDIR $APPPOT_HOME/job
[ -n "$APPPOT_TMPDIR" ] && mount_hostfs $APPPOT_TMPDIR /tmp

# extract a snapshot, if there is any
if [ -n "$APPPOT_CHANGESFILE" ]; then
    merge_changes "$APPPOT_CHANGESFILE"
fi

# ensure that the UID and GID of the user account are the same of the
# mounted "job" directory; we need to do this *after* the changes
# merge because it could have overwritten /etc/passwd
setup_apppot_user \
    ${APPPOT_UID:-1000} ${APPPOT_GID:-1000} \
    ${APPPOT_USER:-user} ${APPPOT_GROUP:-users}

# now set arguments according to the kernel command-line (and remove
# quotes that apppot-start.sh put there)
eval set -- "$@"

# run a job or start an interactive shell
if [ $# -eq 0 ]; then
    if [ -x "$APPPOT_HOME/job/apppot-run" ]; then
        # run the job script as the specified user
        echo "== Running job script '$APPPOT_HOME/job/apppot-run' ..."
        su -l "$APPPOT_USER" -c "$APPPOT_HOME/job/apppot-run"
    elif [ -x "$APPPOT_HOME/apppot-autorun" ]; then
        # run the autostart script as the specified user
        echo "== Running autostart script '$APPPOT_HOME/apppot-autorun' ..."
        su -l "$APPPOT_USER" -c "$APPPOT_HOME/apppot-autorun"
    else
        echo "== Starting shell on /dev/console ..."
        su -l "$APPPOT_USER" -c '/usr/bin/screen /bin/bash'
    fi
else
    # execute command-line
    echo "== Running command-line \"$@\" ..."
    if mountpoint -q "$APPPOT_HOME/job"; then
        # if /home/user/job is mounted, execute job in it
        eval su -l "$APPPOT_USER" -c "'cd $APPPOT_HOME/job; $@'"
    else
        # otherwise, execute in $HOME directory
        eval su -l "$APPPOT_USER" -c "'cd $APPPOT_HOME; $@'"
    fi
fi

echo "==== AppPot done, commencing shutdown ..."
# sleep a few seconds to give /sbin/init time to end the boot sequence
# before shutting down the system
(sleep 1; halt) &
return 0
