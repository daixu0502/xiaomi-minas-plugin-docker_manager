#!/bin/sh
set -u

plugin_user=${1:-}
case "$plugin_user" in u[0-9]*) ;; *) exit 1 ;; esac
home="/home/$plugin_user/plugin/dockermanager"
src=$(readlink "$home/src" 2>/dev/null || true)
[ -x "$src/files/register.sh" ] || exit 1
"$src/files/register.sh" running true "$plugin_user"
/usr/bin/plugincenter -u "$plugin_user" -p dockermanager enable >/dev/null 2>&1 || true

