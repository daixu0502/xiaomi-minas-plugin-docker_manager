#!/bin/sh
set -eu

PLUGIN_USER="${1:-}"
PLUGIN_NAME="dockermanager"
PLUGIN_VERSION="1.0.4"
BUNDLE_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
PAYLOAD_DIR="$BUNDLE_DIR/payload"

fail() { echo "错误：$*" >&2; exit 1; }
[ "$(id -u)" = "0" ] || fail "安装器必须以 root 身份运行"
case "$PLUGIN_USER" in u[0-9]*) ;; *) fail "无效插件用户：$PLUGIN_USER" ;; esac
case "${PLUGIN_USER#u}" in ''|*[!0-9]*) fail "无效插件用户：$PLUGIN_USER" ;; esac
id "$PLUGIN_USER" >/dev/null 2>&1 || fail "设备上不存在用户 $PLUGIN_USER"

for command_name in jq sha256sum plugincenter flock python3 sudo visudo systemctl runuser; do
    command -v "$command_name" >/dev/null 2>&1 || fail "设备缺少命令：$command_name"
done
[ -x /data/docker/docker ] || fail "未找到 /data/docker/docker，请先安装或启用 Docker"
[ -S /var/run/docker.sock ] || fail "Docker socket 不存在：/var/run/docker.sock"

PLUGIN_ROOT="/home/$PLUGIN_USER/plugin"
PLUGIN_HOME="$PLUGIN_ROOT/$PLUGIN_NAME"
existing_src=""
[ -L "$PLUGIN_HOME/src" ] && existing_src=$(readlink "$PLUGIN_HOME/src" 2>/dev/null || true)
case "$existing_src" in
    */"$PLUGIN_USER"/plugin/pluginsrc/"$PLUGIN_NAME") POOL_PLUGIN_ROOT=${existing_src%/pluginsrc/$PLUGIN_NAME} ;;
    *) POOL_PLUGIN_ROOT="/nas/pool0/$PLUGIN_USER/plugin" ;;
esac
[ -d "$(dirname "$POOL_PLUGIN_ROOT")" ] || fail "未找到用户存储池目录：$(dirname "$POOL_PLUGIN_ROOT")"

SRC_PARENT="$POOL_PLUGIN_ROOT/pluginsrc"
TMP_PARENT="$POOL_PLUGIN_ROOT/plugintmp"
SRC_DIR="$SRC_PARENT/$PLUGIN_NAME"
TMP_DIR="$TMP_PARENT/$PLUGIN_NAME"
SCRIPTS_DIR="$PLUGIN_HOME/scripts"
LIST_FILE="/data/plugin/$PLUGIN_USER.list"
WEB_ROOT=$(jq -r '.settings.nginx_plugin // "/data/plugin/www"' /etc/config/plugin)
WEB_USER_DIR="$WEB_ROOT/$PLUGIN_USER"
WEB_LINK="$WEB_USER_DIR/$PLUGIN_NAME"
ICON_DIR="/data/plugin/www/icon"
ICON_FILE="$ICON_DIR/$PLUGIN_NAME.icon"
LOCK_FILE="/data/plugin/.$PLUGIN_USER.$PLUGIN_NAME.lock"
HELPER_DIR="/data/plugin/.dockermanager-system"
HELPER="$HELPER_DIR/docker-manager-helper"
SUDOERS="/etc/sudoers.d/dockermanager-$PLUGIN_USER"
CRON_FILE="/etc/cron.d/dockermanager-$PLUGIN_USER"

[ -f "$LIST_FILE" ] || fail "未找到插件清单：$LIST_FILE"
jq empty "$LIST_FILE" >/dev/null 2>&1 || fail "插件清单不是有效 JSON"
mkdir -p "$PLUGIN_ROOT" "$SRC_PARENT" "$TMP_PARENT" "$PLUGIN_HOME" "$SCRIPTS_DIR" \
    "$WEB_USER_DIR" "$ICON_DIR" "$HELPER_DIR" /etc/sudoers.d

stage_src="$SRC_PARENT/.$PLUGIN_NAME.new.$$"
old_src="$SRC_PARENT/.$PLUGIN_NAME.old.$$"
case "$stage_src" in "$SRC_PARENT"/.*) ;; *) fail "内部暂存路径校验失败" ;; esac
rm -rf "$stage_src"
mkdir -p "$stage_src"
cp -R "$PAYLOAD_DIR/files" "$stage_src/files"
cp -R "$PAYLOAD_DIR/ui" "$stage_src/ui"
cp -R "$PAYLOAD_DIR/system" "$stage_src/system"
chmod 0755 "$stage_src/files/"*.sh "$stage_src/ui/"*.cgi "$stage_src/system/docker-manager-helper"
chmod 0644 "$stage_src/ui/index.html" "$stage_src/ui/app.js" "$stage_src/ui/style.css" "$stage_src/ui/config"

if [ -d "$SRC_DIR" ] && [ ! -L "$SRC_DIR" ]; then mv "$SRC_DIR" "$old_src"; fi
mv "$stage_src" "$SRC_DIR"
[ ! -d "$old_src" ] || rm -rf "$old_src"

cp "$PAYLOAD_DIR/scripts/control" "$SCRIPTS_DIR/control"
chmod 0755 "$SCRIPTS_DIR/control"
rm -f "$PLUGIN_HOME/src" "$PLUGIN_HOME/tmp"
ln -s "$SRC_DIR" "$PLUGIN_HOME/src"
mkdir -p "$TMP_DIR"
ln -s "$TMP_DIR" "$PLUGIN_HOME/tmp"

digest_file="$TMP_DIR/digest.$$"
find "$SRC_DIR" -type f | LC_ALL=C sort | while IFS= read -r f; do sha256sum "$f" | cut -d ' ' -f 1; done > "$digest_file"
abstract=$(sha256sum "$digest_file" | cut -d ' ' -f 1)
rm -f "$digest_file"
plugin_size=$(du -sk "$SRC_DIR" | awk '{print $1 * 1024}')
timestamp=$(date +%s)

info_tmp="$TMP_DIR/INFO.$$"
jq -n --arg version "$PLUGIN_VERSION" --arg abstract "$abstract" --argjson timestamp "$timestamp" --argjson size "$plugin_size" '{
  plugin:"dockermanager", name:"docker", id:19091, version:$version, tags:["tool"],
  timestamp:$timestamp, desc:"容器、镜像与存储卷管理", developer:"Local", publisher:"Local",
  changelog:"修复主页面刷新图标在圆角按钮内未居中的问题",
  system:false, size:$size, port:"", type:"standard", forceupgrade:false,
  ext:{admin:true}, hotplug:[], abstract:$abstract
}' > "$info_tmp"
mv -f "$info_tmp" "$PLUGIN_HOME/INFO"

rm -f "$WEB_LINK"
ln -s "$SRC_DIR/ui" "$WEB_LINK"
if ! python3 "$PAYLOAD_DIR/make_icon.py" "$ICON_FILE"; then cp "$PAYLOAD_DIR/icon.svg" "$ICON_FILE"; fi
chmod 0644 "$ICON_FILE"

entry_file="$TMP_DIR/list-entry.$$"
jq -n --slurpfile frontend "$SRC_DIR/ui/config" --slurpfile info "$PLUGIN_HOME/INFO" --argjson now "$timestamp" '{
  resource:{mpk:"",icon:"",preview:null}, status:"running", install:true, upgrade:false, enable:true,
  changetime:$now, icon:"/icon/dockermanager.icon", progress:"100", frontend:$frontend[0],
  info:($info[0] | del(.abstract)), online:true
}' > "$entry_file"

exec 9>"$LOCK_FILE"
flock -x 9
list_tmp="$LIST_FILE.$PLUGIN_NAME.$$"
backup_file="$LIST_FILE.pre-$PLUGIN_NAME.$timestamp"
cp -p "$LIST_FILE" "$backup_file"
jq --slurpfile entry "$entry_file" '.dockermanager = $entry[0]' "$LIST_FILE" > "$list_tmp"
jq empty "$list_tmp" >/dev/null
chmod --reference="$LIST_FILE" "$list_tmp" 2>/dev/null || chmod 0644 "$list_tmp"
chown --reference="$LIST_FILE" "$list_tmp" 2>/dev/null || chown "$PLUGIN_USER:$PLUGIN_USER" "$list_tmp"
mv -f "$list_tmp" "$LIST_FILE"
rm -f "$entry_file"
flock -u 9

helper_tmp="$HELPER.new.$$"
sudoers_tmp="$SUDOERS.new.$$"
cp "$PAYLOAD_DIR/system/docker-manager-helper" "$helper_tmp"
chown root:root "$HELPER_DIR" "$helper_tmp"
chmod 0755 "$HELPER_DIR" "$helper_tmp"
printf '%s ALL=(root) NOPASSWD: %s\n' "$PLUGIN_USER" "$HELPER" > "$sudoers_tmp"
chown root:root "$sudoers_tmp"
chmod 0440 "$sudoers_tmp"
visudo -cf "$sudoers_tmp" >/dev/null 2>&1 || fail "sudoers 规则校验失败"
mv -f "$helper_tmp" "$HELPER"
mv -f "$sudoers_tmp" "$SUDOERS"

cron_tmp="$CRON_FILE.new.$$"
{
  echo 'SHELL=/bin/sh'
  echo 'PATH=/usr/sbin:/usr/bin:/sbin:/bin'
  echo 'MAILTO=""'
  printf '@reboot root /bin/sh -c '\''sleep 60; /bin/sh %s/files/boot.sh %s'\''\n' "$SRC_DIR" "$PLUGIN_USER"
} > "$cron_tmp"
chmod 0644 "$cron_tmp"
mv -f "$cron_tmp" "$CRON_FILE"
systemctl reload crond.service >/dev/null 2>&1 || true

chown -R "$PLUGIN_USER:$PLUGIN_USER" "$PLUGIN_HOME" "$SRC_DIR" "$TMP_DIR"
chown -h "$PLUGIN_USER:$PLUGIN_USER" "$PLUGIN_HOME/src" "$PLUGIN_HOME/tmp" "$WEB_LINK"
chmod 0700 "$PLUGIN_HOME" "$SRC_DIR" "$TMP_DIR"
chmod 0755 "$SRC_DIR/ui"

runuser -u "$PLUGIN_USER" -- sudo -n "$HELPER" <<'EOF' >/dev/null
{"action":"system_summary"}
EOF
plugincenter -u "$PLUGIN_USER" -p "$PLUGIN_NAME" enable >/dev/null 2>&1 || true

echo "docker $PLUGIN_VERSION 已安装。"
echo "APP 插件清单：$LIST_FILE"
echo "安装前清单备份：$backup_file"
