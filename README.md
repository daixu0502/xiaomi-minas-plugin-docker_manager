# 小米智能存储 Docker 管理插件

在小米智能存储 APP 内管理 Docker，当前插件版本为 `1.0.4`，APP 显示名称为“docker”。

## 功能

- 查看 Docker 运行状态、版本和资源概览
- 查看、创建、启动、停止、重启和删除容器
- 查看容器日志、详情、端口和存储卷映射
- 查看、拉取和删除镜像
- 查看、创建和删除存储卷
- 查看 Docker 网络
- 小米风格移动端页面，兼容 Android 和 iOS

插件页面不直接获得 root 权限，所有 Docker 操作均通过固定动作白名单助手执行。该插件不监听额外网络端口，因此可以安装给多个设备用户。

## 安装

从电脑的 WSL/Linux 运行：

```sh
cd docker-manager-plugin
bash deploy.sh
```

也可以直接指定设备和插件用户：

```sh
bash deploy.sh 192.168.31.100 u123456789
```

在小米智能存储 root SSH 终端内运行：

```sh
cd /home/rootx/docker-manager-plugin
bash deploy.sh u123456789
```

设备必须已经安装并启用 `/data/docker/docker`。

## 卸载

```sh
bash uninstall.sh
```

或指定设备与用户：

```sh
bash uninstall.sh 192.168.31.100 u123456789
```

设备本机运行时：

```sh
bash uninstall.sh u123456789
```

卸载只移除所选用户的 APP 插件、权限规则和管理助手引用，不会删除 Docker 容器、镜像、网络或存储卷。
