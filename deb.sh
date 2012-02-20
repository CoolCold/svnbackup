#!/bin/sh
dpkg-buildpackage -I'.git' -I'.svn' -i -sd -us -uc -rfakeroot

