# KOLBB

办公室下班格斗。Godot 4.7.2，原生 640×360，60Hz 固定模拟。默认窗口 1920×1080，可在设置中切换为 2560×1440（2K）；全屏使用屏幕原生分辨率，保持整数像素缩放。

## 运行

发行版见 [GitHub Releases](https://github.com/lbb-westcity/kolbb/releases)，提供源码、macOS、Windows x64 和 Ubuntu x86_64 服务器包。

解压 `build/KOLBB-macOS.zip`，打开 `KOLBB.app`。包包含 Apple Silicon 和 Intel 两种架构。当前使用本地临时签名，尚未经过 Apple 公证；如系统拦截，在“系统设置 → 隐私与安全性”中允许打开。

Windows 用户解压 `KOLBB-Windows-x64.zip`，运行 `KOLBB.exe`；资源已内嵌，无需安装 Godot。当前 Windows 程序未进行代码签名。

源码启动：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

菜单选择单机或互联网对战。单机可选两名角色、镜像与三档 CPU；99 秒、先赢两局。互联网默认服务器 `49.235.23.27`，一人建房，另一人输入六位房间码，双方准备开始。

## 操作

| 操作 | 默认按键 |
| --- | --- |
| 移动、蹲、跳 | W A S D |
| 轻拳／轻脚 | J / K |
| 重拳／重脚 | U / I |
| 翻滚 | Space，或轻拳＋轻脚 |
| MAX | O，或轻脚＋重拳 |
| 防御 | 按住后；下后防低段 |
| 普通投 | 近身前／后＋重拳 |
| 拆普通投 | 被抓前 7 帧内重拳／重脚 |
| 菜单／出招表 | Esc |
| 判定盒与性能显示 | F3 |

数字指令相对角色朝向：2 下、3 下前、6 前、1 下后、4 后。`236 + 拳` 发射飞行道具。所有必杀、食物规则和 MAX 取消可在游戏“出招表”查看。出招表按角色分页，左右方向键切页，共通操作单独展示；按键提示跟随自定义键位。键位、音量、分辨率、震屏和减少闪光可在设置中调整。

单机切出应用会暂停，恢复前倒数 3 秒。线上菜单保持对战继续，菜单打开期间输入中立；断线与校验不一致不会判任何一方获胜。

## 验证与打包

```sh
bash tools/check.sh
# 32 场包含抖动、5% 丢包和短时断流的完整模拟联机对局：
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/network_chaos.gd
bash tools/export.sh
```

`GODOT_BIN` 可以覆盖引擎路径。导出需要相同版本的 macOS、Windows 和 Linux 导出模板；脚本在 macOS 上使用 `zip` 和 `tar` 打包。

## 服务器

完整流程见 [公网服务器部署与维护](docs/DEPLOYMENT.md)，包含首次部署、UDP 放行、双客户端验收、更新、回滚和故障排查。

服务器包上传至 Ubuntu 24.04 x86_64，解压后执行 `sudo bash install.sh`。仅使用 UDP 7000；需要在云安全组／轻量服务器防火墙允许该入站端口。

服务为 `kolbb.service`，使用独立低权限用户 `kolbb`，开机启动、故障重启。最多 4 个双人房间，无账号或数据库。日志 `/var/log/kolbb/server.log` 每天轮转，保留 7 份。

```sh
sudo systemctl status kolbb
sudo tail -f /var/log/kolbb/server.log
sudo systemctl restart kolbb
```

源码本机服务器：`Godot --headless --path . -- --server`，客户端地址填 `127.0.0.1`。

## 项目资料

- `docs/GDD.md`：战斗、网络及验收规格。
- `docs/VISUAL_BIBLE.md`：角色、舞台和反馈规范。
- `docs/IMPLEMENTATION.md`：实现、资源来源和实际验证记录。
- `design/generated/`：生成原始图稿及音频源文件；发行包不包含该目录。
- `assets/`：运行时图集、字体、音乐、音效和招式数据。

字体为 Noto Sans CJK SC，许可见 `assets/ui/OFL.txt`。角色身份、公司标识与素材源自本项目提供的参考。音乐、图像与音效来源分别记录，不将合成音效标为 Higgsfield 生成。
