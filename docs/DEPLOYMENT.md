# KOLBB 公网服务器部署与维护

本文对应仓库现有的 `tools/export.sh`、`server/install.sh` 和 systemd 配置。命令分为「本机 Mac」和「服务器」两种执行位置。安装、更新和回滚都会重启服务，正在进行的对局会中断；请安排在玩家离开后执行。

## 1. 当前部署信息

2026-09-11 17:03（北京时间）已部署 0.1.2，服务正常监听 UDP 7000。客户端须使用配套 0.1.2 版本。

升级后使用两个本机无窗口客户端连接公网地址，完成 little black 对 JU GUAI 的两场完整对战及再战；双方结算与 CRC 一致（首场 `2172287070`，再战 `651892119`）。验证脚本为 `tests/online_client.gd`，使用 `--full --fast --host 49.235.23.27`。

本次升级前备份位于 `/var/backups/kolbb/20260911-170327`，包含旧服务端程序、systemd 与日志轮转配置。

| 项目 | 当前值 |
| --- | --- |
| 公网地址 | `49.235.23.27` |
| SSH 登录 | `ubuntu@49.235.23.27`，公钥认证 |
| 操作系统 | Ubuntu 24.04 LTS，x86_64 |
| 游戏端口 | **UDP 7000** |
| 服务名／运行用户 | `kolbb.service`／`kolbb` |
| 程序 | `/opt/kolbb/kolbb-server.x86_64` |
| systemd 配置 | `/etc/systemd/system/kolbb.service` |
| 日志／轮转配置 | `/var/log/kolbb/server.log`／`/etc/logrotate.d/kolbb` |
| 状态目录 | `/var/lib/kolbb` |
| 上传暂存目录 | `/home/ubuntu/kolbb-release` |
| 当前网络版本标识 | `kolbb-0.1.2-rules-2-art-3`，见 `scripts/network.gd` |
| 容量 | 最多 4 个房间，每房 2 人 |

服务使用 Godot ENet 中继，无账号或数据库。房间和对局状态保存在内存中，重启后房间码失效，无法恢复未完成对局。服务配置为开机启动，异常退出后等待 3 秒重启，内存上限 1 GiB。

## 2. 首次部署前准备

### 本机与服务器

- 本机安装 Godot 4.7.2，以及相同版本的 macOS、Windows、Linux 导出模板；现有脚本会同时导出三平台。
- 服务器使用 Ubuntu 24.04 x86_64，具备 SSH 登录和 `sudo` 权限。发行程序已嵌入游戏资源，服务器不需要安装 Godot 编辑器。
- 如果已有本次发布的服务器压缩包，可以跳过导出步骤。

**本机 Mac：**确认公钥登录正常。

```sh
ssh -o BatchMode=yes ubuntu@49.235.23.27 'uname -m; lsb_release -ds'
```

架构应为 `x86_64`。出现 `Permission denied (publickey)` 时，通过云控制台将本机 `~/.ssh/id_ed25519.pub` 的内容追加到服务器 ubuntu 用户的 `~/.ssh/authorized_keys`，确保 `.ssh` 目录权限为 `700`、文件权限为 `600`，且归 ubuntu 所有。不要上传私钥。

### 网络规则

在腾讯云控制台对应实例的安全组或轻量应用服务器防火墙中添加入站规则：

| 协议 | 端口 | 来源 | 用途 |
| --- | --- | --- | --- |
| UDP | 7000 | `0.0.0.0/0` | 公网游戏客户端连接 |

保留原有 SSH 登录规则。**TCP 7000 不能代替 UDP 7000。** 如果实例还受到其他网络防火墙限制，也需要允许该 UDP 流量。

**服务器：**检查主机防火墙。

```sh
sudo ufw status
```

当前机器部署时 UFW 未启用。如果实际输出为 `active`，执行 `sudo ufw allow 7000/udp`；无需为了本服务启用 UFW 或改动 SSH 规则。

检查日志轮转工具：

```sh
command -v logrotate
```

若未安装，执行 `sudo apt-get update` 和 `sudo apt-get install -y logrotate`。安装脚本只复制轮转配置，不安装此软件。

## 3. 打包与上传

**本机 Mac，在项目根目录：**

```sh
cd /Users/linyiming/Projects/GodotProjects/kolbb/kolbb
bash tools/check.sh
bash tools/export.sh
tar -tzf build/KOLBB-Ubuntu-server.tar.gz
```

Godot 不在默认位置时，可使用 `GODOT_BIN=/实际路径/Godot bash tools/export.sh`。导出结果：

- `build/KOLBB-Ubuntu-server.tar.gz`：服务器程序、安装脚本、systemd 和日志轮转配置。
- `build/KOLBB-macOS.zip`：配套客户端，发布时应一并保留。
- `build/KOLBB-Windows-x64.zip`：Windows x64 配套客户端。

上传服务器包：

```sh
ssh ubuntu@49.235.23.27 'mkdir -p ~/kolbb-release'
scp build/KOLBB-Ubuntu-server.tar.gz ubuntu@49.235.23.27:kolbb-release/
ssh ubuntu@49.235.23.27
```

最后一条命令进入服务器，后续安装命令在该 SSH 会话中执行。

## 4. 首次安装

**服务器：**

```sh
set -e
mkdir -p ~/kolbb-release/incoming
tar -xzf ~/kolbb-release/KOLBB-Ubuntu-server.tar.gz -C ~/kolbb-release/incoming
cd ~/kolbb-release/incoming
sudo bash install.sh
```

脚本会创建低权限用户 `kolbb` 和所需目录、安装程序及配置、启用开机启动并重启服务。程序目录由 root 管理，状态及日志目录由 kolbb 使用。重复运行脚本可更新安装，但**不会自动备份旧版本**，已有部署请使用第 6 节的更新流程。

## 5. 部署验收

### 服务器状态

**服务器：**

```sh
sudo systemctl is-enabled kolbb
sudo systemctl is-active kolbb
sudo systemctl --no-pager --full status kolbb
sudo ss -lunp 'sport = :7000'
sudo tail -n 60 /var/log/kolbb/server.log
```

预期为 `enabled`、`active`，并出现 UDP 7000 监听。最新启动日志应包含：

```text
KOLBB relay listening UDP 7000 / 4 rooms / kolbb-0.1.2-rules-2-art-3
```

版本以实际发布源码为准。检查最新一次启动后的日志，历史错误记录不等于当前仍然失败。若服务反复重启或日志文件没有新内容，查看启动错误：

```sh
sudo journalctl -u kolbb -n 80 --no-pager
```

### 公网双客户端验收

1. 在两台可联网的客户端上打开同一发行版本的 KOLBB，选择互联网对战；可用不同网络进一步验证公网路径。
2. 服务器地址填 `49.235.23.27`。只填 IP 或域名，不加 `http://`、`https://` 或 `:7000`；端口由程序固定。
3. 一方创建房间，另一方输入六位房间码加入，双方准备。
4. 完成一整场先赢两局的对战，确认双方结算一致，再测试重新对战。
5. 同时查看服务器日志，确认没有新增的脚本错误、断线或同步校验失败。

`ping` 成功、SSH 可用和本机监听正常都不能单独证明公网 UDP 已放行。本服务没有 HTTP 健康检查页面，不能用浏览器或 `curl` 作为游戏连接验收。

## 6. 更新版本

先在本机完成第 3 节的验证、打包和上传，并保存上一版配套客户端。确认玩家已退出后，备份当前安装；以下命令均在**服务器同一个 Bash 会话**中执行：

```sh
set -e
kolbb_backup_dir="/var/backups/kolbb/$(date +%Y%m%d-%H%M%S)"
sudo install -d -m 755 "$kolbb_backup_dir"
sudo cp -p /opt/kolbb/kolbb-server.x86_64 "$kolbb_backup_dir/"
sudo cp -p /etc/systemd/system/kolbb.service "$kolbb_backup_dir/"
sudo cp -p /etc/logrotate.d/kolbb "$kolbb_backup_dir/kolbb.logrotate"
printf '备份目录：%s\n' "$kolbb_backup_dir"

mkdir -p ~/kolbb-release/incoming
tar -xzf ~/kolbb-release/KOLBB-Ubuntu-server.tar.gz -C ~/kolbb-release/incoming
cd ~/kolbb-release/incoming
sudo bash install.sh
```

记录输出的备份目录，随后执行第 5 节验收。安装脚本通过临时文件替换程序，再重启服务；现有日志和状态目录会保留。

客户端和服务器需要相互兼容的规则与网络协议。出现版本不一致提示时，应分发配套客户端；不要只修改 `scripts/network.gd` 的版本字符串绕过检查。对协议或战斗规则的修改需要同步更新版本标识并重新构建两端。

## 7. 回滚

**服务器：**先列出备份。

```sh
sudo ls -1 /var/backups/kolbb
```

将下一段中的示例目录替换为实际存在的备份目录，再执行：

```sh
set -e
kolbb_backup_dir="/var/backups/kolbb/20260910-150000"
sudo test -f "$kolbb_backup_dir/kolbb-server.x86_64"
sudo test -f "$kolbb_backup_dir/kolbb.service"
sudo test -f "$kolbb_backup_dir/kolbb.logrotate"
sudo install -m 755 "$kolbb_backup_dir/kolbb-server.x86_64" /opt/kolbb/kolbb-server.next
sudo mv -f /opt/kolbb/kolbb-server.next /opt/kolbb/kolbb-server.x86_64
sudo install -m 644 "$kolbb_backup_dir/kolbb.service" /etc/systemd/system/kolbb.service
sudo install -m 644 "$kolbb_backup_dir/kolbb.logrotate" /etc/logrotate.d/kolbb
sudo systemctl daemon-reload
sudo systemctl restart kolbb
sudo systemctl --no-pager --full status kolbb
```

回滚后重复第 5 节验收；必要时同时恢复配套客户端。该流程不删除日志，也无法恢复重启前的房间或对局。

## 8. 日常维护与排错

常用只读命令，均在服务器执行：

```sh
sudo systemctl --no-pager --full status kolbb
sudo tail -f /var/log/kolbb/server.log
sudo journalctl -u kolbb --since '30 minutes ago' --no-pager
sudo logrotate --debug /etc/logrotate.d/kolbb
```

`tail -f` 按 Ctrl+C 退出。日志每天检查轮转，保留 7 份归档，空日志不轮转；`--debug` 仅检查配置，不实际轮转。游戏输出写入文件，systemd 启动失败等信息通过 journal 查看。

需要停服、开服或重启时，分别使用 `sudo systemctl stop kolbb`、`sudo systemctl start kolbb`、`sudo systemctl restart kolbb`。停止或重启会清空当前房间。

| 现象 | 检查与处理 |
| --- | --- |
| SSH 成功，但游戏连接超时 | 检查云端规则是否为 **UDP** 7000、是否绑定正确实例，以及主机防火墙。继续检查服务和监听。 |
| 需要判断 UDP 是否到达 | 若已安装 tcpdump，运行 `sudo timeout 20 tcpdump -ni any 'udp port 7000'`，同时让客户端连接。没有入站包时检查云规则、目标地址及客户端网络；有入站包时继续检查回复流量和服务日志。 |
| `Permission denied (publickey)` | 确认用户为 ubuntu、公钥在该用户的 authorized_keys 中、所有者与权限正确；不要修改游戏服务用户来解决 SSH 登录。 |
| 服务启动失败，`209/STDOUT` | 检查 `/var/log/kolbb` 和日志文件是否存在、权限是否正确。当前安装脚本会创建它们，可从完整发布包重新运行安装脚本修复。 |
| 服务启动失败，`203/EXEC` | 检查程序路径、执行权限及服务器架构是否为 x86_64。必要时用 `ldd /opt/kolbb/kolbb-server.x86_64` 检查缺失的动态库。 |
| UDP 7000 绑定失败 | 用 `sudo ss -lunp 'sport = :7000'` 确认占用进程；避免手动启动第二个服务器与 systemd 服务冲突。 |
| 提示版本不一致 | 更新为同一发行版本的客户端与服务器。 |
| 房间不存在／已满 | 确认六位码无误、房主在线、服务未重启；单房上限 2 人，总上限 4 房。 |
| 对局断线或校验失败 | 保存两端版本、发生时间、帧号及相关日志；确认两端资源和战斗规则一致。该情况不会自动判某方获胜，应修复后重新建房。 |

## 9. 相关文件

- [README](../README.md)：客户端运行与操作。
- [实现与验证记录](IMPLEMENTATION.md)：功能、素材和实机验证结果。
- [导出脚本](../tools/export.sh)、[安装脚本](../server/install.sh)。
- [服务配置](../server/kolbb.service)、[日志轮转配置](../server/kolbb.logrotate)。

## 10. Wiki 网站（TCP 7001）

访问地址：[KOLBB 下班百科](http://49.235.23.27:7001/)。2026-09-10 已验证公网 HTTP 200。

Wiki 使用现有 Nginx 提供静态页面，站点目录 `/var/www/kolbb-wiki`，配置 `/etc/nginx/conf.d/kolbb-wiki.conf`，仓库模板为 [server/kolbb-wiki.conf](../server/kolbb-wiki.conf)。网页端口为 **TCP 7001**，与游戏的 **UDP 7000** 分开。新服务器需在云防火墙放行 TCP 7001；本次部署时该端口已可公网访问，UFW 未启用。

内容源是 `docs/wiki/*.md`，样式为 `docs/wiki/wiki.css`。构建使用 Python 3 与 Python-Markdown（本机已有 3.4.1；新环境可使用 `python3 -m pip install Markdown==3.4.1`）。无需前端构建工具或网站数据库。文档之间的链接转成网页链接，图片复制到站点目录，源代码和其他项目资料链接指向 GitHub。

**本机，在项目根目录构建、检查、上传：**

```sh
python3 tools/build_wiki.py
python3 tests/wiki_test.py
COPYFILE_DISABLE=1 tar --no-xattrs -czf build/KOLBB-wiki.tar.gz -C build/wiki .
scp build/KOLBB-wiki.tar.gz ubuntu@49.235.23.27:kolbb-release/
```

**服务器，备份后更新内容：**

```sh
set -e
kolbb_wiki_backup="/var/backups/kolbb-wiki/$(date +%Y%m%d-%H%M%S)"
sudo install -d -m 755 "$kolbb_wiki_backup"
sudo cp -a /var/www/kolbb-wiki "$kolbb_wiki_backup/"
sudo tar -xzf ~/kolbb-release/KOLBB-wiki.tar.gz --no-same-owner -C /var/www/kolbb-wiki
sudo find /var/www/kolbb-wiki -type d -exec chmod 755 {} +
sudo find /var/www/kolbb-wiki -type f -exec chmod 644 {} +
curl --fail --silent --output /dev/null --write-out '%{http_code}\n' http://127.0.0.1:7001/
```

只更新静态内容无需重载 Nginx。首次安装或修改端口配置时，将仓库 `server/kolbb-wiki.conf` 上传并安装到 `/etc/nginx/conf.d/kolbb-wiki.conf`，执行 `sudo nginx -t` 成功后再执行 `sudo systemctl reload nginx`。无需重启游戏服务。访问日志为 `/var/log/nginx/kolbb-wiki.access.log`，错误日志为 `/var/log/nginx/kolbb-wiki.error.log`。

最后在本机验证 `curl --fail http://49.235.23.27:7001/` 并打开网页。HTTP 成功只验证 Wiki，不代表游戏 UDP 连接已经通过验收。
