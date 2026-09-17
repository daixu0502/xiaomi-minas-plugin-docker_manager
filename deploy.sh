#!/usr/bin/env bash
set -Eeuo pipefail

NAS_IP="${1:-}"
PLUGIN_USER="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
用法：
  bash deploy.sh
  bash deploy.sh <小米智能存储IP> [插件用户]

远程安装未提供 IP 时会提示输入；未提供插件用户时会扫描并选择。
在小米智能存储 root 终端内运行时自动直接安装，不需要输入 IP。
EOF
}

if [[ "$NAS_IP" == "-h" || "$NAS_IP" == "--help" ]]; then
    usage
    exit 0
fi

DIRECT_INSTALL=false
if [[ "$(id -u)" == "0" ]] && command -v plugincenter >/dev/null 2>&1 && [[ -f /etc/config/plugin ]]; then
    DIRECT_INSTALL=true
    if [[ "${1:-}" =~ ^u[0-9]+$ ]]; then
        PLUGIN_USER="$1"
        NAS_IP=""
    fi
fi

if [[ "$DIRECT_INSTALL" != "true" && -z "$NAS_IP" ]]; then
    if [[ ! -t 0 ]]; then
        echo "错误：未提供设备 IP；非交互环境请运行：bash deploy.sh <设备IP> [插件用户]" >&2
        exit 2
    fi
    read -r -p "请输入小米智能存储 IP：" NAS_IP
fi

required_commands=(tar mktemp)
if [[ "$DIRECT_INSTALL" != "true" ]]; then
    required_commands+=(ssh scp sort)
fi
for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "错误：未找到命令：$command_name" >&2
        exit 3
    }
done

ssh_options=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
ssh_target="${NAS_IP:+root@$NAS_IP}"

choose_plugin_user() {
    local choices=("$@")
    if (( ${#choices[@]} == 0 )); then
        echo "错误：没有扫描到可安装插件的 u123456789 用户。" >&2
        exit 2
    fi
    if (( ${#choices[@]} == 1 )); then
        PLUGIN_USER="${choices[0]}"
        echo "自动选择唯一用户：$PLUGIN_USER"
        return
    fi
    if [[ ! -t 0 ]]; then
        echo "错误：扫描到多个用户，非交互环境请显式指定用户。" >&2
        exit 2
    fi
    echo "请选择要安装 docker 插件的用户："
    PS3="请输入序号："
    select selected_user in "${choices[@]}"; do
        if [[ -n "$selected_user" ]]; then
            PLUGIN_USER="$selected_user"
            break
        fi
        echo "无效序号，请重新选择。"
    done
}

if [[ "$DIRECT_INSTALL" != "true" ]]; then
    if [[ ! "$NAS_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "错误：无效的 IPv4 地址：$NAS_IP" >&2
        exit 2
    fi
    IFS='.' read -r -a ip_octets <<< "$NAS_IP"
    for octet in "${ip_octets[@]}"; do
        (( 10#$octet <= 255 )) || { echo "错误：无效的 IPv4 地址：$NAS_IP" >&2; exit 2; }
    done
fi

if [[ -z "$PLUGIN_USER" ]]; then
    users=()
    if [[ "$DIRECT_INSTALL" == "true" ]]; then
        shopt -s nullglob
        for list_file in /data/plugin/u*.list; do
            candidate="${list_file##*/}"
            candidate="${candidate%.list}"
            [[ "$candidate" =~ ^u[0-9]+$ ]] && [[ -d "/home/$candidate" ]] && users+=("$candidate")
        done
        shopt -u nullglob
    else
        mapfile -t users < <(ssh "${ssh_options[@]}" "$ssh_target" \
            'for f in /data/plugin/u*.list; do u=${f##*/}; u=${u%.list}; case "$u" in u[0-9]*) [ -d "/home/$u" ] && printf "%s\n" "$u" ;; esac; done' | sort -u)
    fi
    choose_plugin_user "${users[@]}"
fi

[[ "$PLUGIN_USER" =~ ^u[0-9]+$ ]] || { echo "错误：插件用户应类似 u123456789。" >&2; exit 2; }

work_dir="$(mktemp -d)"
cleanup() {
    if [[ -n "${work_dir:-}" && -d "$work_dir" && "$work_dir" == /tmp/* ]]; then
        rm -rf "$work_dir"
    fi
}
trap cleanup EXIT HUP INT TERM

stage_dir="$work_dir/docker-manager-plugin"
mkdir -p "$stage_dir"
cp -R "$SCRIPT_DIR/payload" "$stage_dir/payload"
cp "$SCRIPT_DIR/remote-install.sh" "$stage_dir/remote-install.sh"

if [[ "$DIRECT_INSTALL" == "true" ]]; then
    echo "检测到正在小米智能存储本机运行，将直接安装（不使用 SSH）……"
    /bin/sh "$stage_dir/remote-install.sh" "$PLUGIN_USER"
    echo "安装完成。请刷新小米智能存储 APP，打开 docker。"
    exit 0
fi

archive="$work_dir/docker-manager-plugin.tgz"
tar -C "$work_dir" -czf "$archive" docker-manager-plugin
remote_suffix="$$-$RANDOM"
remote_archive="/tmp/docker-manager-plugin-$remote_suffix.tgz"
remote_dir="/tmp/docker-manager-plugin-$remote_suffix"

echo "正在上传到 $ssh_target……"
scp "${ssh_options[@]}" "$archive" "$ssh_target:$remote_archive"
echo "正在安装 docker 插件……"
ssh "${ssh_options[@]}" "$ssh_target" \
    "REMOTE_ARCHIVE='$remote_archive' REMOTE_DIR='$remote_dir' PLUGIN_USER='$PLUGIN_USER' /bin/sh -s" <<'REMOTE_WRAPPER'
set -eu
cleanup_remote() {
    case "$REMOTE_DIR" in /tmp/docker-manager-plugin-*) rm -rf "$REMOTE_DIR" ;; esac
    case "$REMOTE_ARCHIVE" in /tmp/docker-manager-plugin-*.tgz) rm -f "$REMOTE_ARCHIVE" ;; esac
}
trap cleanup_remote EXIT HUP INT TERM
mkdir -p "$REMOTE_DIR"
tar -xzf "$REMOTE_ARCHIVE" -C "$REMOTE_DIR"
/bin/sh "$REMOTE_DIR/docker-manager-plugin/remote-install.sh" "$PLUGIN_USER"
REMOTE_WRAPPER

echo "安装完成。请刷新小米智能存储 APP，打开 docker。"
