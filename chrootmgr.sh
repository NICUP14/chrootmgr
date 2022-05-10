#!/system/bin/sh

# Checks if the specified environment is properly configured
check_environment()
{
    [ ! -d "$CHROOTMGR_ENV" ] && return 1
    ! $BUSYBOX chroot "$CHROOTMGR_ENV" /bin/uname > /dev/null && return 1
    [ ! -x "${CHROOTMGR_ENV}${CHROOTMGR_EXEC}" ] && return 1

    return 0
}

# Checks if the environment is already mounted
environment_is_running()
{
    # Checks if the filesystems are mounted
    for mount_point in proc dev dev/pts dev/shm sys system sdcard; do
        ! $BUSYBOX mountpoint -q "$CHROOTMGR_ENV"/$mount_point && return 1
    done

    return 0;
}

# Mounts the chroot environment
start_environment()
{
    # Allows the use of setuid binaries
    $BUSYBOX mount -o remount,suid /data

    # Links the standard streams to their file descriptor
    [ ! -e "/dev/fd" ] && ln -s /proc/self/fd /dev/
    [ ! -e "/dev/stdin" ] && ln -s /proc/self/fd/0 /dev/stdin
    [ ! -e "/dev/stdout" ] && ln -s /proc/self/fd/1 /dev/stdout
    [ ! -e "/dev/stderr" ] && ln -s /proc/self/fd/2 /dev/stderr

    # Mounts the /proc filesystem
    mkdir -p "$CHROOTMGR_ENV"/proc
    ! $BUSYBOX mountpoint -q "$CHROOTMGR_ENV"/proc && $BUSYBOX mount -t proc proc "$CHROOTMGR_ENV"/proc

    # Mounts the /dev filesystem
    mkdir -p "$CHROOTMGR_ENV"/dev
    ! $BUSYBOX mountpoint -q "$CHROOTMGR_ENV"/dev && $BUSYBOX mount --bind /dev "$CHROOTMGR_ENV"/dev

    # Mounts the /dev/pts filesystem
    ! $BUSYBOX mountpoint -q "$CHROOTMGR_ENV"/dev/pts && $BUSYBOX mount -t devpts devpts "$CHROOTMGR_ENV"/dev/pts

    # Mounts the /dev/shm filesystem
    mkdir -p "$CHROOTMGR_ENV"/dev/shm
    ! $BUSYBOX mountpoint -q "$CHROOTMGR_ENV"/dev/shm && $BUSYBOX mount -o rw,nosuid,nodev,mode=1777 -t tmpfs tmpfs "$CHROOTMGR_ENV"/dev/shm

    # Mounts the /sdcard filesystem
    mkdir -p "$CHROOTMGR_ENV"/sdcard
    ! $BUSYBOX mountpoint -q "$CHROOTMGR_ENV"/sdcard && $BUSYBOX mount -t sdcardfs sdcard "$CHROOTMGR_ENV"/sdcard

    # Mounts the /sys filesystem
    mkdir -p "$CHROOTMGR_ENV"/sys
    ! $BUSYBOX mountpoint -q "$CHROOTMGR_ENV"/sys && $BUSYBOX mount -t sysfs sys "$CHROOTMGR_ENV"/sys

    # Mounts the /system filesystem
    mkdir -p "$CHROOTMGR_ENV"/system
    ! $BUSYBOX mountpoint -q "$CHROOTMGR_ENV"/system && $BUSYBOX mount --bind /system "$CHROOTMGR_ENV"/system

    # Creates the /etc/resolv.conf file
    true > "$CHROOTMGR_ENV"/etc/resolv.conf
    for server in 1 2 3 4; do
        [ -z "$(getprop net.dns$server)" ] && break
        echo "nameserver $(getprop net.dns$server)" >> "$CHROOTMGR_ENV"/etc/resolv.conf
    done

    # Creates the /etc/hosts file
    true > "$CHROOTMGR_ENV"/etc/hosts
    echo "127.0.0.1     localhost $CHROOTMGR_HNAME" >> "$CHROOTMGR_ENV"/etc/hosts
    echo "::1           localhost ip6-localhost ip6-loopback" >> "$CHROOTMGR_ENV"/etc/hosts
    $BUSYBOX hostname "$CHROOTMGR_HNAME"

    # Sets the appropriate environment variables
    export TMPDIR=/tmp
    export PATH=/usr/bin:/usr/sbin:/bin:/usr/local/bin:/usr/local/sbin:"$PATH"

    $BUSYBOX resize
}

# Unmounts the chroot environment
stop_environment()
{
    # Kills all processes currently using the environment
    kill "$($BUSYBOX fuser "$CHROOTMGR_ENV")" > /dev/null

    # Disallows the use of suid binaries
    $BUSYBOX mount -o remount,nosuid /data

    # Unmounts previously mounted filesystems
    for mount_point in proc dev/pts dev/shm dev sdcard sys system; do
        $BUSYBOX mountpoint -q "$CHROOTMGR_ENV"/$mount_point && $BUSYBOX umount "$CHROOTMGR_ENV"/${mount_point}
    done
}

if [ $# -eq 0 ]; then
    echo "Usage: chrootmgr (start|stop|check) <environment>"
    echo "Manage chroot environments"
    exit
fi

# Checks for popular busybox install locations
[ -x /sbin/busybox ] && BUSYBOX=/sbin/busybox
[ -x /system/bin/busybox ] && BUSYBOX=/system/bin/busybox
[ -x /system/xbin/busybox ] && BUSYBOX=/system/xbin/busybox
[ -x /data/local/bin/busybox ] && BUSYBOX=/data/local/bin/busybox

# Checks if the busybox binary exists
[ -z $BUSYBOX ] && exit 1

# Check if the user has root permissions 
[ "$(id -u)" -ne 0 ] && exit 2

# Configures parameters
CHROOTMGR_CMD=$1
[ -z "$CHROOTMGR_ENV" ] && CHROOTMGR_ENV=$2
[ -z "$CHROOTMGR_EXEC" ] && CHROOTMGR_EXEC=/bin/su
CHROOTMGR_HNAME="$(basename "$CHROOTMGR_ENV")"

! check_environment && exit 3

# Executes specified command
[ "$CHROOTMGR_CMD" = "stop" ] && stop_environment
[ "$CHROOTMGR_CMD" = "check" ] && ! environment_is_running && exit
[ "$CHROOTMGR_CMD" = "start" ] && start_environment && $BUSYBOX chroot "$CHROOTMGR_ENV" $CHROOTMGR_EXEC

exit 0