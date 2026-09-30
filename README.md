# 小米智能存储 Docker 管理插件

在手机 APP 和电脑客户端中管理 Docker，插件列表名称为“docker”。当前插件版本：`1.1.2`。

## 本版界面更新

统一六插件的页头位置、状态卡片、统计信息顺序、圆角、间距和刷新按钮。电脑客户端随窗口使用全部可用宽度，手机页头显示当前插件名称，浅色使用雾灰背景，手机深色使用中性炭灰。样式限定在插件内部，不修改客户端全局字体；保留原有配置和功能。

## 功能

- 管理容器，查看日志、详情、端口和挂载。
- 更新容器镜像，按原配置重建并在失败时尝试恢复旧容器。
- 启动、停止或重启 Docker 引擎及全部容器。
- 管理镜像、网络和存储卷。

## 安装包结构

每个插件目录可单独复制和使用，只需要一个操作入口：

- `manage.sh`：包含环境识别、用户选择、安装、卸载、传输和清理逻辑。
- `payload/`：安装所需的网页、服务、图标及权限助手。
- `README.md`：使用说明；Mihomo 另附第三方许可说明。

旧的 `deploy.sh`、`uninstall.sh`、`remote-*.sh` 及公共辅助脚本已合并到 `manage.sh`。需要在 NAS 上执行的内部脚本由它临时生成，用完自动清理，不需要另外下载或保留多个入口脚本。

首次使用可以直接打开菜单：

```bash
bash manage.sh
```

菜单中选择“安装 / 更新”或“卸载”。命令行和自动化则明确指定 `install` 或 `uninstall`。

## 运行环境

- **NAS 本机**：自动识别小米插件配置和 `plugincenter`，使用 root 直接执行，无需填写 IP。
- **WSL / Linux**：自动通过 root SSH 连接设备；未填写 IP 时交互询问。支持密钥或交互式密码认证。
- NAS 存储池必须已经正常挂载，目标用户已在小米客户端初始化。
- 非交互运行需要可用的 SSH 密钥；扫描到多个用户时必须明确选择。
- 源码中不保存真实设备地址、账户或订阅信息。下面 IP 和用户 ID 均为示例。

## 安装与更新

在插件目录内运行：

```bash
bash manage.sh install
```

统一执行五步：识别环境 → 扫描用户 → 显示计划并预检查 → 逐用户执行 → 汇总结果。

交互列表显示已安装/未安装状态，可以输入单个序号、逗号分隔的多个序号（如 `1,3`）或 `all`。只有一个用户时自动选择。

WSL / Linux 指定 NAS 和多个用户：

```bash
bash manage.sh install --ip 192.168.31.100 --users u123456789,u987654321
```

NAS 本机指定多个用户：

```bash
bash manage.sh install --users u123456789,u987654321
```

安装给全部符合条件的用户：

```bash
# WSL / Linux
bash manage.sh install --ip 192.168.31.100 --all-users
# NAS 本机
bash manage.sh install --all-users
```

兼容原来的位置参数：

```bash
bash manage.sh install 192.168.31.100 u123456789
# NAS 本机
bash manage.sh install u123456789
```

重复安装保留现有配置，并更新插件文件。批量执行中某个用户失败时，继续处理后续用户；最后显示成功和失败列表，有失败时返回非零退出码。已成功用户不自动回滚；请解决错误后只重试失败用户。

## 卸载

```bash
bash manage.sh uninstall
```

卸载列表只显示已安装该插件的用户，同样支持单选、多选和全部选择。执行前会显示范围并要求输入 `yes`。

```bash
# WSL / Linux，卸载所选用户
bash manage.sh uninstall --ip 192.168.31.100 --users u123456789,u987654321
# NAS 本机，卸载全部已安装用户
bash manage.sh uninstall --all-users
```

自动化卸载必须明确使用 `--yes`：

```bash
bash manage.sh uninstall --ip 192.168.31.100 --users u123456789 --yes
```

卸载前先停止所选用户的插件，并将存在的 `etc/`、`var/`、`INFO` 和插件清单备份到：

```text
/home/<用户>/plugin/.reserve/dockermanager/<时间>-<进程号>/
```

备份不会自动恢复。重新安装后，如需恢复配置，应先停止插件并按需恢复相关数据；备份可能含密钥，请妥善保管。

保留 Docker 引擎、容器、镜像、网络和存储卷。其他用户仍在使用时，共享图标和权限助手会保留。

## 只查看，不执行

```bash
# 扫描用户；NAS 本机运行时省略 --ip
bash manage.sh install --ip 192.168.31.100 --list-users
bash manage.sh uninstall --ip 192.168.31.100 --list-users

# 核对计划及用户存储池，不下载、不安装、不卸载
bash manage.sh install --ip 192.168.31.100 --all-users --dry-run
bash manage.sh uninstall --ip 192.168.31.100 --all-users --dry-run

bash manage.sh install --help
bash manage.sh uninstall --help
```

## 本插件说明

NAS 需已安装 `/data/docker/docker`。本插件不另开监听端口；不同用户分别注册页面和权限，操作的是同一 Docker 引擎。卸载某一用户的插件不会停止或删除容器。

只有 Docker Manager 和定时任务的所有用户均已卸载时，才清理公共组件执行文件和 cron。保留受保护的登记/锁目录和备份；Docker 数据目录不在卸载范围内。

## 公共权限组件

与定时任务共用 `/data/.minas-privileged/minas-helper`（组件 1.x、API v1）。两个安装包各自携带完整公共组件，可按任意顺序独立安装；安装器检查版本、拒绝权限模块降级和不兼容主版本。卸载一个插件不会删除另一个仍需使用的组件。

CGI 通过 `sudo -n /data/.minas-privileged/minas-helper dockermanager` 发送 JSON 请求。助手按固定接口调用本机 Docker CLI、Unix socket 和固定的 Docker systemd 服务，不开放额外端口，不授予任意 root shell，也不放宽 docker.sock 权限。

两个插件的 Docker 写操作共用全局锁，异步升级和批量操作的整个过程都持有锁；查询与进度轮询仍可使用，冲突写操作返回忙。外部 SSH、其他插件和 Docker 自动重启不受此锁限制。升级/卸载公共组件时拒绝中断正在执行的操作。

授权由 root 登记在 `registry.json`，sudoers 只允许对应模块入口，不使用参数通配符。**Docker 容器创建与宿主机挂载属于接近 root 的高信任能力，仅应安装给可信管理员。同一 NAS 账户的插件共用 UID，授权是该账户的权限并集，不代表插件之间存在强隔离。**

公共组件及迁移/移除备份位于 `/data/.minas-privileged-backups/<时间>/`。组件、父路径和模块必须由 root 所有且普通用户不可写；旧的 `/data/plugin/.dockermanager-system/` 不再作为新版本的提权入口。开机注册脚本降权为对应 NAS 用户执行。

手机 Android/iOS 跟随 WebView 提供的系统深浅色信号；Docker 的卡片、输入框、弹窗和按钮均有深色样式。电脑客户端固定使用雾蓝灰。`palette.css` 同时由 CGI 静态路由提供；更新后请退出插件重进，若宿主不传递主题信号仍需在 APP 侧确认主题设置。

## 常见问题

- **SSH 连接失败**：先确认能执行 `ssh root@设备IP`。非交互环境不会等待密码输入；连接失败会明确报错，不会被当成“没有用户”。
- **存储池未挂载**：先在客户端确认硬盘和存储池恢复正常，再重试。脚本不会在未挂载的空目录里安装。
- **找不到用户**：先在小米客户端初始化该用户，再用 `--list-users` 检查；用户必须存在于扫描列表。
- **NAS 本机提示需要 root**：切换到 root 后运行。不要在本机命令里传设备 IP。
- **缺少文件或命令**：使用完整安装包，并根据错误安装或恢复必要依赖。
- **安装后仍显示旧页面**：完全关闭并重新打开手机 APP 或电脑客户端中的插件。
- **批量操作部分失败**：依据最后的结果列表重试失败用户；错误前可能已写入该用户的部分文件，请保留日志。
- **暂存清理失败**：脚本会显示 NAS 上的具体暂存路径；确认没有安装任务使用它后再手动清理。

安装包不包含设备运行配置、订阅凭据、私有账户、日志或安装备份。自动生成的 `.cache/`、`__pycache__/`、临时压缩包和 `*.tmp` 不需要随安装包分发。
