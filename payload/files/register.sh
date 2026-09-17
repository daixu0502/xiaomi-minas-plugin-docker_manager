#!/bin/sh
set -eu

status=${1:-running}; enabled=${2:-true}; plugin_user=${3:-${PLUG_USER:-}}
case "$plugin_user" in u[0-9]*) ;; *) exit 1 ;; esac
case "${plugin_user#u}" in ''|*[!0-9]*) exit 1 ;; esac
case "$status" in running|stopped) ;; *) exit 1 ;; esac
case "$enabled" in true|false) ;; *) exit 1 ;; esac

SRC_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
PLUGIN_HOME="/home/$plugin_user/plugin/dockermanager"
LIST_FILE="/data/plugin/$plugin_user.list"
INFO_FILE="$PLUGIN_HOME/INFO"
FRONTEND_FILE="$SRC_DIR/ui/config"
LOCK_FILE="/data/plugin/.$plugin_user.dockermanager.lock"
[ -f "$INFO_FILE" ] && [ -f "$FRONTEND_FILE" ] || exit 1
[ -f "$LIST_FILE" ] || printf '{}\n' > "$LIST_FILE"
jq empty "$LIST_FILE" >/dev/null 2>&1 || exit 1

exec 9>"$LOCK_FILE"; flock -x 9
tmp="$LIST_FILE.dockermanager-register.$$"
jq --slurpfile frontend "$FRONTEND_FILE" --slurpfile info "$INFO_FILE" --arg status "$status" --argjson enabled "$enabled" --argjson now "$(date +%s)" '
  .dockermanager = ((.dockermanager // {}) + {
    resource:((.dockermanager.resource // {mpk:"",icon:"",preview:null})), status:$status,
    install:true, upgrade:false, enable:$enabled, changetime:$now, icon:"/icon/dockermanager.icon",
    progress:"100", frontend:$frontend[0], info:($info[0] | del(.abstract)), online:true
  })' "$LIST_FILE" > "$tmp"
jq empty "$tmp" >/dev/null
chmod --reference="$LIST_FILE" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
chown --reference="$LIST_FILE" "$tmp" 2>/dev/null || true
mv -f "$tmp" "$LIST_FILE"; flock -u 9

