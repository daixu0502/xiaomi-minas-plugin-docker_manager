#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd -P)
plugin_user=$(printf '%s\n' "$SCRIPT_DIR" | sed -n 's#^/nas/pool[^/]*/\(u[0-9][0-9]*\)/plugin/pluginsrc/dockermanager/ui$#\1#p')
if [ -z "$plugin_user" ]; then plugin_user=$(stat -c '%U' "$0" 2>/dev/null || true); fi
case "$plugin_user" in u[0-9]*) ;; *) plugin_user=$(id -un) ;; esac

HELPER="/data/plugin/.dockermanager-system/docker-manager-helper"
INFO_FILE="/home/$plugin_user/plugin/dockermanager/INFO"

json_header() {
    printf 'Content-Type: application/json; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n\r\n'
}

static_header() {
    printf 'Content-Type: %s\r\n' "$1"
    printf 'Cache-Control: no-cache, no-store, must-revalidate\r\n\r\n'
}

serve_frontend() {
    request_path=${REQUEST_URI:-/index.html}; request_path=${request_path%%\?*}
    case "$request_path" in
        */app.js) static_header 'application/javascript; charset=utf-8'; cat "$SCRIPT_DIR/app.js" ;;
        */style.css) static_header 'text/css; charset=utf-8'; cat "$SCRIPT_DIR/style.css" ;;
        *) static_header 'text/html; charset=utf-8'; cat "$SCRIPT_DIR/index.html" ;;
    esac
    exit 0
}

json_error() {
    json_header
    jq -n --arg error "$1" '{ok:false,error:$error}'
    exit 0
}

get_action() {
    printf '%s' "${QUERY_STRING:-}" | tr '&' '\n' | sed -n 's/^action=\([A-Za-z0-9_-]*\)$/\1/p' | head -n 1
}

read_body() {
    length=${CONTENT_LENGTH:-0}
    case "$length" in ''|*[!0-9]*) return 1 ;; esac
    [ "$length" -le 131072 ] || return 2
    if [ "$length" -eq 0 ]; then printf '{}'; else dd bs=1 count="$length" 2>/dev/null; fi
}

action=$(get_action)
[ -n "$action" ] || serve_frontend
case "$action" in
    system_summary|container_list|container_stats|container_action|container_logs|container_inspect|container_create|image_list|image_pull|image_remove|volume_list|volume_create|volume_remove|network_list) ;;
    *) json_error "未知操作" ;;
esac
[ "${REQUEST_METHOD:-GET}" = "POST" ] || json_error "API 仅接受 POST 请求"
[ -x "$HELPER" ] || json_error "Docker 权限助手未安装"

body=$(read_body) || json_error "请求内容无效或过大"
printf '%s' "$body" | jq empty >/dev/null 2>&1 || json_error "请求不是有效 JSON"
request=$(printf '%s' "$body" | jq --arg action "$action" '. + {action:$action}') || json_error "无法处理请求"
response=$(printf '%s' "$request" | sudo -n "$HELPER" 2>/dev/null) || json_error "无法调用 Docker 权限助手"
printf '%s' "$response" | jq empty >/dev/null 2>&1 || json_error "权限助手返回了无法解析的数据"
plugin_version=$(jq -r '.version // "1.0.4"' "$INFO_FILE" 2>/dev/null || printf '1.0.4')

json_header
printf '%s' "$response" | jq --arg pluginVersion "$plugin_version" '. + {pluginVersion:$pluginVersion}'
