# KOLBB

办公室下班格斗。Godot 4.7.2，原生 640×360，60Hz 固定模拟。默认窗口 1920×1080，可在设置中切换为 2560×1440（2K）；全屏使用屏幕原生分辨率，默认保持整数像素缩放，可在视频设置中调整。

## 运行

发行版见 [GitHub Releases](https://github.com/lbb-westcity/kolbb/releases)，提供源码、macOS、Windows x64 和 Ubuntu x86_64 服务器包。

解压 `build/KOLBB-macOS.zip`，打开 `KOLBB.app`。包包含 Apple Silicon 和 Intel 两种架构。当前使用本地临时签名，尚未经过 Apple 公证；如系统拦截，在“系统设置 → 隐私与安全性”中允许打开。

Windows 用户解压 `KOLBB-Windows-x64.zip`，运行 `KOLBB.exe`；资源已内嵌，无需安装 Godot。当前 Windows 程序未进行代码签名。

源码启动：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

菜单选择单机或互联网对战。单机可选四名角色、镜像与三档 CPU；99 秒、先赢两局。互联网默认服务器 `49.235.23.27`，一人建房，另一人输入六位房间码，双方准备开始。

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

必杀只需依次按上下左右，无需斜方向。`下、前 + 拳` 发射飞行道具：面朝右时依次按 S、D，再按 J 或 U；朝左时把 D 换成 A。数字简写为 2 下、6 前、4 后、8 上。所有必杀、食物规则和 MAX 取消可在游戏“出招表”查看。出招表按角色分页，左右方向键切页，共通操作单独展示；按键提示跟随自定义键位。设置按视频、图形、按键和声音分类；支持自动保存、当前分类恢复默认、帧率上限、垂直同步与整数缩放。

单机切出应用会暂停，恢复前倒数 3 秒。线上菜单保持对战继续，菜单打开期间输入中立；断线与校验不一致不会判任何一方获胜。

## 验证与打包

```sh
bash tools/check.sh
# 三档 CPU、三组对位、每组 32 个种子并换边，共 576 场：
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/balance.gd -- --tournament 32 2000
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

- [版本管理与发布](docs/VERSION_CONTROL.md)：提交、版本号、发布检查和回滚；[更新记录](CHANGELOG.md)。
- [三角色平衡验证](docs/BALANCE.md)：当前数值调整、换边对局结果与复测方法。

- [在线 Wiki · 下班百科](http://49.235.23.27:7001/)（[文档版](docs/wiki/README.md)）：新手操作、角色技能、完整招式数据、战斗机制、食物与联机指南。

- `docs/GDD.md`：战斗、网络及验收规格。
- `docs/VISUAL_BIBLE.md`：角色、舞台和反馈规范。
- `docs/IMPLEMENTATION.md`：实现、资源来源和实际验证记录。
- `design/generated/`：生成原始图稿及音频源文件；发行包不包含该目录。
- `assets/`：运行时图集、字体、音乐、音效和招式数据。

字体为 Noto Sans CJK SC 与 Bungee，许可分别见 `assets/ui/OFL.txt`、`assets/ui/Bungee-OFL.txt`。角色身份、公司标识与素材源自本项目提供的参考。音乐、图像与音效来源分别记录，不将合成音效标为 Higgsfield 生成。

第三角色 **little black** 已加入：篮球、铁山靠、音爆、露出鸡脚、鸡你太美。左手持尤尼克斯羽毛球拍，支持镜像、三档 CPU 与联机；详见[角色指南](docs/wiki/little-black.md)。已发布桌面版 0.1.3 使用 rules-3。当前开发版新增第四角色 **linbin**：老弟、喝茶、涛声依旧、收工咯～；详见[角色指南](docs/wiki/linbin.md)。开发版使用 rules-4，联机双方及服务端必须同步更新；此次未部署服务端。

## 练习与操作优化

主菜单的「练习模式」沿用选人界面，提供不限时木桩、站立／自动防御、自动恢复血量与能量。暂停菜单可切换木桩和恢复选项；画面显示最近六次输入及实际出招，点「重置位置」、按 F5 或手柄 View 可立即重置。练习不计入累计战绩。

桌面支持手柄方向键／左摇杆，X/A/Y/B 对应轻拳／轻脚／重拳／重脚，RB 翻滚、LB MAX、Start 暂停，菜单 A 确认、B 返回。出招表按键提示跟随键盘／手柄切换。结算显示本局最高连击、实际造成伤害（含削血、敌方误吃汉堡，扣除过量伤害）与最后一回合剩余生命；统计随回滚恢复，但不参与战斗规则校验。

菜单和设置预览只加载两名角色的 core 动作；开战再加载参战角色完整动作，返回菜单释放战斗图集。更新角色动画后运行 `Godot --headless --path . --script tools/prepare_previews.gd` 重建轻量预览资源。`tests/improvements.gd` 覆盖练习、手柄、资源切换、音效优先级、半格能量及统计回滚。

2026-09-12，M2 Pro / Godot 4.7.2 的 little black 镜像场景测得显存 260.23 MiB（此前同脚本记录 611.15 MiB）；本次实际帧间隔 P95 为 19.364ms、末次 102 FPS。这次确认了资源占用下降，未据此认定帧率提升。数据见 `build/performance.json`。
