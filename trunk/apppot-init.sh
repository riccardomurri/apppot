#! /bin/sh
### BEGIN INIT INFO
# Provides:          apppot
# Required-Start:    $syslog
# Required-Stop:     $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Set up the AppPot environment.
# Description:       Sets up the the AppPot environment, including mounting
#                    hostfs directories, setting up MPI networking, etc.
#                    and then runs the job specified by users on the kernel
#                    command-line.  If no job is specified, starts SCREEN
#                    on the first console.
### END INIT INFO
#
# Author: Riccardo Murri <riccardo.murri@gmail.com>
VERSION=0.2

# PATH should only include /usr/* if it runs after the mountnfs.sh script
PATH=/sbin:/usr/sbin:/bin:/usr/bin
DESC="Starting AppPot $VERSION ..."
NAME=apppot
SCRIPTNAME=/etc/init.d/$NAME

# Read configuration variable file if it is present
[ -r /etc/default/$NAME ] && . /etc/default/$NAME

# Load the VERBOSE setting and other rcS variables
. /lib/init/vars.sh

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.0-6) to ensure that this file is present.
. /lib/lsb/init-functions


## auxiliary functions

# value EXPR
#
# Given an EXPR of the form `name=value`, output the `value` part.
#
value () {
    echo "$1" | cut -d= -f2-
}

# process_command_line
#
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
process_command_line () {
    if ! [ -r /proc/cmdline ]; then
        return 1
    fi
    set -- `cat /proc/cmdline`
    while [ $# -gt 0 ]; do
        case "$1" in
            apppot.user=*)   export APPPOT_USER="$(value "$1")" ;;
            apppot.uid=*)    export APPPOT_UID="$(value "$1")" ;;
            apppot.group=*)  export APPPOT_GROUP="$(value "$1")" ;;
            apppot.gid=*)    export APPPOT_GID="$(value "$1")" ;;
            apppot.jobdir=*) export APPPOT_JOBDIR="$(value "$1")" ;;
            apppot.tmpdir=*) export APPPOT_TMPDIR="$(value "$1")" ;;
            # `--` means end of kernel params and start of job arguments
            --) shift; break ;;
        esac
        shift
    done
    return 0
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
    cat >> /etc/sudoers <<__EOF__

# user '$user' enabled by '$0'
$user  ALL=(ALL) ALL
__EOF__

    # define $APPPOT_HOME to the user home directory
    export APPPOT_HOME="`getent passwd "$user" | cut -d: -f6`"
    chown -R "$uid":"$gid" "$APPPOT_HOME"

    return 0
}


# mount_hostfs HOSTDIR MOUNTDIR
#
# Mount host directory HOSTDIR onto local mount point MOUNTDIR
#
mount_hostfs () { 
    hostdir=${1:?Missing required parameter HOSTDIR to 'mount_hostfs'}
    mountdir=${2:?Missing required parameter MOUNTDIR to 'mount_hostfs'}

    mkdir -p $mountdir
    mount host $mountdir -t hostfs -o $hostdir
}


#
# Function that starts the daemon/service
#
do_start()
{
    # Return
    #   0 if daemon has been started
    #   1 if daemon was already running
    #   2 if daemon could not be started
    process_command_line
    setup_apppot_user

    [ -n "$APPPOT_JOBDIR" ] && mount_hostfs $APPPOT_JOBDIR $APPPOT_HOME/job
    [ -n "$APPPOT_TMPDIR" ] && mount_hostfs $APPPOT_TMPDIR /tmp

    # extract a snapshot, if there is any
    if [ -r "$APPPOT_HOME/job/apppot-changes.tgz" ]; then
        apppot-snap.sh merge "$APPPOT_HOME/job/apppot-changes.tgz"
    fi

    # run a job or start an interactive shell
    if [ $# -eq 0 ]; then
        if [ -x "$APPPOT_HOME/job/apppot-run" ]; then
            # run the job script as the specified user
            su -l "$APPPOT_USER" -c "$APPPOT_HOME/job/apppot-run"
        if [ -x "$APPPOT_HOME/apppot-autorun" ]; then
            # run the autostart script as the specified user
            su -l "$APPPOT_USER" -c "$APPPOT_HOME/apppot-autorun"
        else
            start_screen_on_console
        fi
    else
        # execute command-line
        eval su -l "$APPPOT_USER" -c \'"$@"\'
    fi

    # all done, shutdown the AppPot machine after a few seconds
    # timeout (to give `init` time to settle)
    (sleep 5; halt) &
    return 0
}


#
# Function that stops the daemon/service
#
do_stop()
{
    # Return
    #   0 if daemon has been stopped
    #   1 if daemon was already stopped
    #   2 if daemon could not be stopped
    #   other if a failure occurred
    halt
}


case "$1" in
  start)
        [ "$VERBOSE" != no ] && log_daemon_msg "Starting $DESC" "$NAME"
        do_start
        case "$?" in
                0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
                2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
        esac
        ;;
  stop)
        [ "$VERBOSE" != no ] && log_daemon_msg "Stopping $DESC" "$NAME"
        do_stop
        case "$?" in
                0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
                2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
        esac
        ;;
  #status)
        #status_of_proc "$DAEMON" "$NAME" && exit 0 || exit $?
        #;;
  #reload|force-reload)
        #
        # If do_reload() is not implemented then leave this commented out
        # and leave 'force-reload' as an alias for 'restart'.
        #
        #log_daemon_msg "Reloading $DESC" "$NAME"
        #do_reload
        #log_end_msg $?
        #;;
  restart|force-reload)
        #
        # If the "reload" option is implemented then remove the
        # 'force-reload' alias
        #
        log_daemon_msg "Restarting $DESC" "$NAME"
        do_stop
        case "$?" in
          0|1)
                do_start
                case "$?" in
                        0) log_end_msg 0 ;;
                        1) log_end_msg 1 ;; # Old process is still running
                        *) log_end_msg 1 ;; # Failed to start
                esac
                ;;
          *)
                # Failed to stop
                log_end_msg 1
                ;;
        esac
        ;;
  *)
        #echo "Usage: $SCRIPTNAME {start|stop|restart|reload|force-reload}" >&2
        echo "Usage: $SCRIPTNAME {start|stop}" >&2
        exit 3
        ;;
esac

:
