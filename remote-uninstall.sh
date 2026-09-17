#!/bin/sh
set -eu

PLUGIN_USER="${1:-}"
PLUGIN_NAME="dockermanager"
case "$PLUGIN_USER" in u[0-9]*) ;; *) echo "错误：无效插件用户" >&2; exit 1 ;; esac
case "${PLUGIN_USER#u}" in ''|*[!0-9]*) echo "错误：无效插件用户" >&2; exit 1 ;; esac
[ "$(id -u)" = "0" ] || { echo "错误：必须以 root 身份运行" >&2; exit 1; }

PLUGIN_HOME="/home/$PLUGIN_USER/plugin/$PLUGIN_NAME"
LIST_FILE="/data/plugin/$PLUGIN_USER.list"
SRC_DIR=""; TMP_DIR=""
[ -L "$PLUGIN_HOME/src" ] && SRC_DIR=$(readlink "$PLUGIN_HOME/src" 2>/dev/null || true)
[ -L "$PLUGIN_HOME/tmp" ] && TMP_DIR=$(readlink "$PLUGIN_HOME/tmp" 2>/dev/null || true)
SUDOERS="/etc/sudoers.d/dockermanager-$PLUGIN_USER"
HELPER_DIR="/data/plugin/.dockermanager-system"

plugincenter -u "$PLUGIN_USER" -p "$PLUGIN_NAME" disable >/dev/null 2>&1 || true
if [ -f "$LIST_FILE" ] && jq empty "$LIST_FILE" >/dev/null 2>&1; then
    tmp="$LIST_FILE.$PLUGIN_NAME-uninstall.$$"
    jq 'del(.dockermanager)' "$LIST_FILE" > "$tmp"
    chmod --reference="$LIST_FILE" "$tmp" 2>/dev/null || chmod 0644 "$tmp"
    chown --reference="$LIST_FILE" "$tmp" 2>/dev/null || chown "$PLUGIN_USER:$PLUGIN_USER" "$tmp"
    mv -f "$tmp" "$LIST_FILE"
fi

rm -f "$SUDOERS" "/data/plugin/www/$PLUGIN_USER/$PLUGIN_NAME" "/etc/cron.d/dockermanager-$PLUGIN_USER" "/data/plugin/.$PLUGIN_USER.$PLUGIN_NAME.lock"
case "$SRC_DIR" in /nas/pool*/"$PLUGIN_USER"/plugin/pluginsrc/"$PLUGIN_NAME") rm -rf "$SRC_DIR" ;; "") ;; *) echo "警告：未删除异常 src 路径：$SRC_DIR" >&2 ;; esac
case "$TMP_DIR" in /nas/pool*/"$PLUGIN_USER"/plugin/plugintmp/"$PLUGIN_NAME") rm -rf "$TMP_DIR" ;; "") ;; *) echo "警告：未删除异常 tmp 路径：$TMP_DIR" >&2 ;; esac
[ "$PLUGIN_HOME" = "/home/$PLUGIN_USER/plugin/dockermanager" ] || exit 1
rm -rf "$PLUGIN_HOME"

if ! find /etc/sudoers.d -maxdepth 1 -type f -name 'dockermanager-u*' | grep -q .; then
    rm -rf "$HELPER_DIR"
    rm -f /data/plugin/www/icon/dockermanager.icon
fi
systemctl reload crond.service >/dev/null 2>&1 || true
echo "docker 插件已从 $PLUGIN_USER 卸载；Docker 资源未被删除。"
