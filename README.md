# 小米智能存储 docker 插件

这是一个面向小米智能存储手机 APP 的本地 docker 管理插件，界面和操作方式参考 Portainer，但不启动额外管理容器，也不开放 Docker TCP 端口。

## 功能

- Docker 引擎概览、容器/镜像/Volume 数量与空间占用
- 查看全部容器及状态、端口、网络、挂载
- 启动、停止、重启、暂停、继续和删除容器
- 查看容器最近日志和结构化详情
- 创建容器，支持镜像、名称、重启策略、网络、端口、挂载、环境变量和启动命令
- 拉取、查看和删除镜像
- 创建、查看和删除命名 Volume
- iOS/Android 安全区适配和左右滑动切页

## 安装

需要先确保：

1. 小米智能存储已开启 root SSH。
2. Docker 服务已安装并运行，设备存在 `/data/docker/docker`。
3. 电脑可使用密钥执行 `ssh root@设备IP`。

在电脑或 WSL 中进入本目录：

```sh
bash deploy.sh
```

安装器会提示输入设备 IP，扫描设备上的 `u数字` 用户并让你选择。也可以直接指定：

```sh
bash deploy.sh 192.168.31.100 u123456789
```

也可以把整个目录复制到小米智能存储，在 root SSH 终端中运行 `bash deploy.sh`。本机安装不会询问 IP。

## 权限与安全

网页不会直接访问 `/var/run/docker.sock`。安装器会创建 root 所有的：

```text
/data/plugin/.dockermanager-system/docker-manager-helper
```

插件用户只能通过 `sudo` 调用这个固定助手，不能附加命令行参数。助手只接受大小受限的 JSON，并把操作映射到预先实现的 Docker 子命令；所有外部输入都通过参数数组传给 Docker，不经过 Shell 拼接或 `eval`。

Docker 管理本身属于高权限操作：容器挂载主机目录、映射端口或运行不可信镜像都可能影响设备安全。请只安装可信镜像，并谨慎确认删除操作。

## 卸载

```sh
bash uninstall.sh
```

卸载器会提示输入设备 IP，并扫描哪些用户安装了 docker 插件。卸载只删除插件界面、清单、权限助手授权和插件文件，不会删除现有容器、镜像、Volume 或 Docker 数据。
