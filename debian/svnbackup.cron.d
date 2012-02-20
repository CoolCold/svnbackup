#
# Regular cron jobs for the svnbackup package
#
17 */2     * * *   root    [ -x /usr/bin/svnbackup-backup ] && /usr/bin/svnbackup-backup -c /etc/svnbackup.conf


