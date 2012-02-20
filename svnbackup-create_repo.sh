#!/bin/bash
# vim:ts=4:sw=4:et:

# script to create repository on repo server

# $Id: svnbackup-create_repo.sh 72 2010-09-29 18:26:42Z coolcold $

PROGNAME=$(basename $0)
CONFFILE_DEF=/etc/svnbackup.conf


print_usage() {
    echo "Usage: $PROGNAME [-c <config file path>] -H <hostname>"
    echo "       use -h to show this help"
}

print_help() {
    echo "$PROGNAME"
    echo ""
    print_usage
    echo ""
    echo "This will create subversion repository for <hostname>"
}


if [ -z $1 ];then
	print_help
	exit 1
fi

# parsing arguments

while getopts ":hc:H:" Option; do
  case $Option in
    h)
      print_help
      exit 0
      ;;
    c)
      CONFFILE=${OPTARG}
      ;;
    H)
      REPOHOST=${OPTARG}
      ;;
    *)
      print_help
      exit 0
      ;;
  esac
done
shift $(($OPTIND - 1))

# end of  arguments parsing
if [ -z "$CONFFILE" ];then CONFFILE=${CONFFILE_DEF};fi

if [ ! -f $CONFFILE ];then
    echo "configuration file $CONFFILE doesn't exist. Check path you've specified?"
    exit 1
fi

if ! . $CONFFILE;then
    echo "cannot include config file $CONFFILE . Check permissions?"
    exit 2
fi

if [ -z $REPOHOST ];then
    echo "hostname was not specified"
    echo ""
    print_help
    exit 1
fi

#checking for username repository will be accessed by
if [ -z $SVNUSER ];then
    echo "username for subversion repository rw access was not specified, set SVNUSER variable in config $CONFFILE"
    exit 1
fi

#checking for directory owner in user:group format repository will be owned by
if [ -z $REPOOWNED ];then
    echo "repository dir owner was not specified, specify REPOOWNED variable in config $CONFFILE . Format is uid:gid acceptable by chown"
    exit 1
fi


# if INSTALLPCHOOK = YES post-commit template should be copied into hooks, checking is path specified and exist
if [ "x${INSTALLPCHOOK}" == "xYES" ];then
    
    if [ -z ${PCHOOK_TMPL} ];then
        echo "INSTALLPCHOOK option is set to ${INSTALLPCHOOK} , but PCHOOK_TMPL is empty, specify variable value in config file ${CONFFILE}"
        exit 1
    fi

    #checking for existance
    if [ ! -r "${PCHOOK_TMPL}" ];then
        echo "Template file ${PCHOOK_TMPL} is not readable"
        exit 1
    fi
fi

if [ -z $REPOSPATH ];then echo "subversion repositories path variable REPOSPATH is not set, check your config $CONFFILE";exit 2;fi
if ! which svn >/dev/null;then echo "subversion not found in your PATH, consider installing subversion"; exit 2;fi

REPOPATH="${REPOSPATH}${REPOHOST}"

#does destination folder already exist?
if [ -d $REPOPATH ];then
	echo "Directory $REPOPATH already exist, exiting"
	exit 1
fi

CMD="svnadmin create --fs-type fsfs $REPOPATH"
echo "the next command will be executed"
echo "$CMD"

repopasswd=$(openssl passwd .)
echo "password for repository $1 will be ${repopasswd} "
echo "You need to paste it on the remote host $REPOHOST"

repo_data=$($CMD 2>&1)
repo_res=$?

if [ $repo_res -ne 0 ];then
    echo "failed to create repository for $REPOHOST in $REPOPATH"
    echo "message is:"
    echo "$repo_data"
    exit 2
fi


#generating configs
cat <<EOF>"${REPOPATH}/conf/authz"
[/]
${SVNUSER} = rw
EOF

cat<<EOF>"${REPOPATH}/conf/passwd"
[users]
${SVNUSER} = ${repopasswd}
EOF

cat<<EOF>"${REPOPATH}/conf/svnserve.conf"
[general]
anon-access = none
auth-access = write
password-db = passwd
authz-db = authz
realm = ${REPOHOST} repository
EOF

#installing hook
if [ "x${INSTALLPCHOOK}" == "xYES" ];then
    PCHOOKPATH="${REPOPATH}/hooks/post-commit"
    echo "installing post-commit hook into ${PCHOOKPATH} ..."
    PCHOOK_CONTENT=$(sed "s/BHOST_TEMPLATE/${REPOHOST}/" "${PCHOOK_TMPL}")
    if ! echo "${PCHOOK_CONTENT}"|grep -q "${REPOHOST}";then
        #failed
        echo "template update failed, post-commit hook won't be installed"
    else
        echo "${PCHOOK_CONTENT}" > "${PCHOOKPATH}"
        chmod +x "${PCHOOKPATH}"
    fi
else
    echo "skipping installation of post-commit hook..."
fi

chown -R "${REPOOWNED}" ${REPOPATH}

echo "done"

