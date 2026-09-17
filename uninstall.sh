#!/usr/bin/env bash
set -Eeuo pipefail

NAS_IP="${1:-}"
PLUGIN_USER="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DIRECT_UNINSTALL=false
if [[ "$(id -u)" == "0" ]] && command -v plugincenter >/dev/null 2>&1 && [[ -f /etc/config/plugin ]]; then
    DIRECT_UNINSTALL=true
    if [[ "${1:-}" =~ ^u[0-9]+$ ]]; then
        PLUGIN_USER="$1"
        NAS_IP=""
    fi
fi

if [[ "$DIRECT_UNINSTALL" != "true" && -z "$NAS_IP" ]]; then
    if [[ ! -t 0 ]]; then
        echo "错误：未提供设备 IP；非交互环境请运行：bash uninstall.sh <设备IP> [插件用户]" >&2
        exit 2
    fi
    read -r -p "请输入小米智能存储 IP：" NAS_IP
fi

ssh_options=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

choose_plugin_user() {
    local choices=("$@")
    if (( ${#choices[@]} == 0 )); then
        echo "没有扫描到已安装 docker 插件的用户。" >&2
        exit 2
    fi
    if (( ${#choices[@]} == 1 )); then
        PLUGIN_USER="${choices[0]}"
        echo "自动选择唯一已安装用户：$PLUGIN_USER"
        return
    fi
    [[ -t 0 ]] || { echo "错误：扫描到多个已安装用户，请显式指定用户。" >&2; exit 2; }
    echo "请选择要卸载 docker 插件的用户："
    PS3="请输入序号："
    select selected_user in "${choices[@]}"; do
        [[ -n "$selected_user" ]] && { PLUGIN_USER="$selected_user"; break; }
        echo "无效序号，请重新选择。"
    done
}

if [[ "$DIRECT_UNINSTALL" != "true" ]]; then
    [[ "$NAS_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "错误：无效的 IPv4 地址：$NAS_IP" >&2; exit 2; }
    for command_name in ssh sort; do command -v "$command_name" >/dev/null 2>&1 || exit 3; done
fi

if [[ -z "$PLUGIN_USER" ]]; then
    users=()
    if [[ "$DIRECT_UNINSTALL" == "true" ]]; then
        shopt -s nullglob
        for f in /data/plugin/u*.list; do
            u="${f##*/}"; u="${u%.list}"
            [[ "$u" =~ ^u[0-9]+$ ]] && { jq -e '.dockermanager.install == true' "$f" >/dev/null 2>&1 || [[ -d "/home/$u/plugin/dockermanager" ]]; } && users+=("$u")
        done
        shopt -u nullglob
    else
        mapfile -t users < <(ssh "${ssh_options[@]}" "root@$NAS_IP" \
            'for f in /data/plugin/u*.list; do u=${f##*/}; u=${u%.list}; case "$u" in u[0-9]*) if jq -e ".dockermanager.install == true" "$f" >/dev/null 2>&1 || [ -d "/home/$u/plugin/dockermanager" ]; then printf "%s\n" "$u"; fi ;; esac; done' | sort -u)
    fi
    choose_plugin_user "${users[@]}"
fi

[[ "$PLUGIN_USER" =~ ^u[0-9]+$ ]] || { echo "错误：无效插件用户。" >&2; exit 2; }
if [[ "$DIRECT_UNINSTALL" == "true" ]]; then
    exec /bin/sh "$SCRIPT_DIR/remote-uninstall.sh" "$PLUGIN_USER"
fi
ssh "${ssh_options[@]}" "root@$NAS_IP" /bin/sh -s -- "$PLUGIN_USER" < "$SCRIPT_DIR/remote-uninstall.sh"
