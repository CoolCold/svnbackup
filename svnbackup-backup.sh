#!/bin/bash
# vim:ts=4:sw=4:et:
# script to make an automated commit of /etc and/or other configuration
# directories into subversion repository

# $Id: svnbackup-backup.sh 104 2011-03-15 15:28:30Z coolcold $
MYREVISION='$Id: svnbackup-backup.sh 104 2011-03-15 15:28:30Z coolcold $'
MYVERSION="0.2.1 , revision: ${MYREVISION}"
PROGNAME=$(basename $0)

#walking around sudo/su variables & subversion configs
HOME=/root 
export HOME

#setting messages to be in English
LANG=C
export LANG

#LOCKFILE=/var/run/svnbackup.pid
CONFFILE=/etc/svnbackup.conf
#CONFFILE=svnbackup.conf
LOGGER='logger -t svnbackup --'
INITSVN=NO
TS_START=$(date +%s) #when we started


#error messages
ERROR_NOREPO="No repository found in"
ERROR_CANTGETPASS="Can't get password"

function mylog() {
    if [ -z "$1" ];then return 0;fi #exiting if msg is empty
    if [ "x$1" == "x-e" ];then
        echo "$2"
        $LOGGER "$2"
    else
        $LOGGER "$1"
    fi
}

function myexit() {
    extcode="$1"
    if [ -z "$1" ];then extcode=0;fi
    #doing some cleanup
    if ! [ "x$2" == "xNO" ];then
        if ! [ -z "$svncopy" ];then mylog "removing temporary copy ${svncopy}";rm -rf "${svncopy}";fi
        mylog "removing lockfile $LOCKFILE";rm -rf $LOCKFILE
    fi
    exit $extcode
}

print_usage() {
    echo "Usage: $PROGNAME -c <config file path> [-I]"
    echo ""
    echo "-I     should be used for first run, to make subversion client save password and such"
    echo "       use -h to show this help"
}

print_help() {
    echo "svnbackup - $MYVERSION"
    echo ""
    print_usage
    echo ""
    echo "This script intended to make an automated commit of /etc and/or other configuration"
    echo "directories into subversion repository, so allowing to keep history of changes"
}


mylog "starting svnbackup script version: $MYVERSION"

if [[ $# -eq "0"  ]]; then
    #no arguments were specified...very, very bad
    print_help
    mylog -e "no configuration file was specified, please read help on usage"
    exit 1
fi


# parsing arguments

while getopts ":hIc:" Option; do
  case $Option in
    h)
      print_help
      exit 0
      ;;
    c)
      CONFFILE=${OPTARG}
      ;;
    I)
      INITSVN="YES"
      ;;
    *)
      print_help
      exit 0
      ;;
  esac
done
shift $(($OPTIND - 1))

# end of  arguments parsing

if [ ! -f $CONFFILE ];then
	mylog -e "configuration file $CONFFILE doesn't exist. Check path you've specified?"
	exit 1
fi

if ! . $CONFFILE;then
	mylog -e "cannot include config file $CONFFILE . Check permissions?" 
	exit 2
fi

#validating
if [ -z $SERVER ];then mylog -e "this server name variable SERVER is not set, check your config $CONFFILE";exit 2;fi
if [ -z $LOCKFILE ];then mylog -e "lockfile variable LOCKFILE is not set, check your config $CONFFILE";exit 2;fi
if [ -z $STATEFILE ];then mylog -e "status file variable STATEFILE is not set, check your config $CONFFILE";exit 2;fi
if [ -z $SVNREPOTMP ];then mylog -e "tmp storage variable SVNREPOTMP for data is not set, check your config $CONFFILE";exit 2;fi
if [ -z $SVNPATH ];then mylog -e "svn repo path variable SVNPATH is not set, check your config $CONFFILE";exit 2;fi

#username should be really needed only on first run, then data should be cached
if [ -z $SVNUSER ];then mylog -e "username for svn repo access variable SVNUSER is not set, check your config $CONFFILE";exit 2;fi
if ! which svn >/dev/null;then mylog -e "subversion not found in your PATH, consider installing subversion"; exit 2;fi
if ! which rsync >/dev/null;then mylog -e "rsync not found in your PATH, consider installing rsync";exit 2;fi

svncopy="${SVNREPOTMP}/${SERVER}"

#getting include dirs
includes=$(grep "^include_dir=" ${CONFFILE}|sed 's/^include_dir=//';exit ${PIPESTATUS[0]})
includes_res=$?
if [ $includes_res -ne 0 ];then
	#grep failed to find any include dirs :(
	mylog -e "couldn't find any directories to include, exiting..."
	exit 2
fi

#echo "includes are"
#echo "${includes}"
#array will be 1 based cuz count func returns total count
c=1
while read line
do
	include_dir[$c]="${line}"
	#echo "c is $c"
	((c++))
	#echo "elements count:${#include_dir[@]}"
done < <(echo "${includes}")

ic=$((${#include_dir[@]} - 1))
#echo "elements count:$ic"
#c=1
#while [ $c -le $ic ];do
#	echo "i is $c, and element is ${include_dir[$c]}"
#	((c++))
#done


#setting lock
mylog "setting lockfile $LOCKFILE"
exec 200<> $LOCKFILE
flock -n -x 200
if [ $? -ne 0 ];then
	mylog -e "setting lock on $LOCKFILE failed"
	myexit 1 "NO"
fi
echo $$ >&200

#prepare local copy
function preparelc() {
    rm -rf ${svncopy}
    if ! mkdir -m 700 -p ${svncopy};then mylog -e "problem while creating directory ${svncopy}";return 2;fi
    mylog "doing checkout from repository $SVNPATH/$SERVER into ${svncopy} ..."
    
    #are were doing svn init?
    if [ $INITSVN = "YES" ];then
        if ! svn --username "${SVNUSER}" co $SVNPATH/$SERVER ${svncopy};then
            mylog -e "checkout failed"
            return 2
        fi
    else
        if ! svn co --non-interactive $SVNPATH/$SERVER ${svncopy};then
            mylog "checkout failed"
            return 2
        fi
    fi
    chmod 700 ${svncopy}
    chown root:root ${svncopy}
}

function synclc() {
#this function should sync local data onto checkouted ones
#this we'll do svn commit
    
    mylog "doing local sync for $1"
    if [ "x$1" == "x" ];then return 2;fi
    if ! pushd ${svncopy} >/dev/null 2>&1;then
        mylog -e "can't pushd into ${svncopy}"
        return 2
    fi
    #creating subdirectory 
    newdir=".$1"
    mkdir -p "$newdir"
    if ! pushd "${newdir}" >/dev/null 2>&1;then
        mylog -e "can't pushd into ${newdir}"
        return 2
    fi

    if ! rsync -a --delete --exclude=.svn "$1/" . > /dev/null;then
        mylog -e "rsync failed, can not continue"
        return 3
    fi
    popd >/dev/null 2>&1

    #pushd ${svncopy}/etc >/dev/null 2>&1
}

function dosvncommit() {


    if ! pushd ${svncopy} >/dev/null 2>&1;then
        mylog -e "can't pushd into ${svncopy}"
        return 2
    fi

    svnstatus="$(svn status)"

    if [ "x${svnstatus}" != "x" ]; then
        #echo "The following changes were made to /etc:"
        tmpfile=$(mktemp /tmp/svn.XXXXXX)
        if ! svn status >${tmpfile} 2>&1;then
            mylog -e "svn status failed, can't continue"
            rm -rf ${tmpfile}
            return 2
        fi
        #cat ${tmpfile}
        #echo ""
        svntoadd=$(cat ${tmpfile} | egrep '^\?')
        for i in  ${svntoadd}; do
            if [ "${i}" != "?" ]; then
            svn add ${i}>/dev/null
            fi
        done
        svntodel=$(cat ${tmpfile} | egrep '^\!')
        for i in  ${svntodel}; do
            if [ "${i}" != "!" ]; then
            svn rm ${i} >/dev/null
            fi
        done
        svntoupstatus=$(cat ${tmpfile} | egrep '^\~')
        for i in  ${svntoupstatus}; do
            if [ "${i}" != '~' ]; then
            rm ${i}
            svn remove ${i} >/dev/null
            #svn add ${i} >/dev/null
            fi
        done
        if ! svn commit -m "Auto-commit on $(date)" > /dev/null;then
            echo "commit failed. check access rights?"
            rm -f ${tmpfile}
            return 2
        fi
        rm -f ${tmpfile}
    fi
    popd >/dev/null 2>&1
}

function updatestatus() {
    TS_END=$(date +%s)
    TS_DIFF=$((TS_END - TS_START))
    #format - "current timestamp" "time taken"
    echo "$TS_END $TS_DIFF" > ${STATEFILE}
}

#doing checkout from repo
preparelc_out=$(preparelc 2>&1)
preparelc_res=$?
if [ $preparelc_res -ne 0 ];then
    mylog -e "checkouting from repo failed, exiting"
    mylog -e "mesage is: $preparelc_out"
    if echo "$preparelc_out"|fgrep -q "${ERROR_NOREPO}";then
        mylog -e "Do you have created repository on $SVNPATH/$SERVER ? "
        mylog -e "You may need to init subversion client configuration, view $PROGNAME -h and README for more information"
    elif echo "$preparelc_out"|fgrep -q "${ERROR_CANTGETPASS}";then
        mylog -e "Have you done initial run of ${PROGNAME} ? view $PROGNAME -h and README for more information"
    fi
    myexit 2
else
    mylog "repository copy checkouted"
    
    #are we initializing repo?
    if [ $INITSVN = "YES" ];then
        #just exiting cuz everything should be done already
        mylog -e "exiting because of init mode"
        myexit 0
    fi
fi

#iterating over paths to be backuped
c=1
while [ $c -le $ic ];do
	#echo "i is $c, and element is ${include_dir[$c]}"
    so=$(synclc "${include_dir[$c]}" 2>&1)
    synclc_res=$?
    if [ $synclc_res -eq 3 ];then
        mylog -e "dying because of rsync error:"
        mylog -e "$so"
        myexit 2
    elif [ $synclc_res -ne 0 ];then
        mylog -e "dying because of unknown local sync error"
        myexit 2
    fi
	((c++))
done

#exit 2

co=$(dosvncommit 2>&1)
co_res=$?
if [ $co_res -ne 0 ];then
    mylog -e "svn commit failed:"
    mylog -e "$co"
    myexit 2
fi

#since we got here, everything should be ok, updating success status
updatestatus
mylog "time taken: $TS_DIFF seconds"
myexit 0

