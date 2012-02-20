#!/bin/bash
# vim:ts=4:sw=4:et:

# script to check time difference with last successfull repo commit

# $Id: check_svnbackup.sh 102 2011-03-09 14:27:07Z coolcold $

PROGNAME=$(basename $0)
CONFFILE_DEF=/etc/svnbackup.conf
TIMETAKEN=0

#nagios constants
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

ncode=$STATE_OK
ntext=""

print_usage() {
    echo "Usage: $PROGNAME [-c <config file path>] -T <seconds> [-t <seconds>]"
    echo ""
    echo "if -c is omitted, default config path \"$CONFFILE_DEF\" is used"
    echo ""
    echo "-T is for \"timestamp\" difference in seconds, if difference with"
    echo "current timestamp is larger than <seconds> then WARNING will be generated"
    echo ""
    echo "-t is for \"time taken\", if <seconds> is less than real time taken,"
    echo "WARNING will be generated"
    echo ""
    echo "use -h to show this help"
}

print_help() {
    echo "$PROGNAME"
    echo ""
    print_usage
    echo ""
    echo "This plugin can check time difference with last successfull repo commit"
    echo "for svnbackup tool and how much time did it take"
}


if [ -z $1 ];then
	print_help
	exit $STATE_UNKNOWN
fi

# parsing arguments

while getopts ":hc:T:t:" Option; do
  case $Option in
    h)
      print_help
      exit $STATE_UNKNOWN
      ;;
    c)
      CONFFILE=${OPTARG}
      ;;
    T)
      TS_DIFF=${OPTARG}
      ;;
    t)
      TIMETAKEN=${OPTARG}
      ;;
    *)
      print_help
      exit $STATE_UNKNOWN
      ;;
  esac
done
shift $(($OPTIND - 1))

# end of  arguments parsing
if [ -z "$CONFFILE" ];then CONFFILE=${CONFFILE_DEF};fi

if [ ! -f $CONFFILE ];then
    echo "configuration file $CONFFILE doesn't exist. Check path you've specified?"
    exit $STATE_UNKNOWN
fi

if ! . $CONFFILE;then
    echo "cannot include config file $CONFFILE . Check permissions?"
    exit $STATE_UNKNOWN
fi

if [ -z $TS_DIFF ];then
    echo "TIMESTAMP difference was not specified"
    echo ""
    print_help
    exit $STATE_UNKNOWN
fi

if [ -z $STATEFILE ];then echo "svnbackup state file variable \"STATEFILE\" is empty, check your config $CONFFILE";exit $STATE_CRITICAL;fi
if ! [ -r $STATEFILE ];then echo "svnbackup state file \"$STATEFILE\" is unreadable, check access permissions";exit $STATE_CRITICAL;fi

#STATEFILE=blabla.txt
#using bashism to read data without subshell
read -a statedata < <( cat $STATEFILE 2>/dev/null)
readcode=$?
if [ $readcode -ne 0 ];then
    echo "error while reading $STATEFILE contents"
    exit $STATE_UNKNOWN
fi
#echo "${statedata[0]}" #timestamp
#echo "${statedata[1]}" #time taken

#check values for timestamp diff
CURTS=$(date +%s)
tshuman=$(date -d @${statedata[0]})
tdiff=$(( $CURTS - ${statedata[0]} ))
ntext="difference is $tdiff seconds, limit $TS_DIFF, last update on: $tshuman"
if [ $tdiff -gt $TS_DIFF ];then
    ncode=$STATE_WARNING
#else
#    ncode=$STATE_OK
fi

#checking values for update time
tttext="not checking for taken time"
if [ $TIMETAKEN -gt 0 ];then #let's do timetaken test
    if [ ${statedata[1]} -gt $TIMETAKEN ];then
        tttext="update took too much time - ${statedata[1]} seconds"
        ncode=$STATE_WARNING
    else
        tttext="update time below treshhold - ${statedata[1]} seconds"
    fi
fi
ntext="svnbackup check - $ntext, $tttext"

case $ncode in
    $STATE_OK)
        nprefix="OK"
        ;;
    $STATE_WARNING)
        nprefix="WARNING"
        ;;
    $STATE_CRITICAL)
        nprefix="CRITICAL"
        ;;
    $STATE_UNKNOWN)
        nprefix="UNKNOWN"
        ;;
    $STATE_DEPENDENT)
        nprefix="DEPENDENT"
        ;;
    *)
        nprefix="unknown code"
        ;;
esac
echo "${nprefix}:${ntext}"
exit $ncode

