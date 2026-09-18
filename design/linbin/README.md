# linbin 美术资源

使用内置 ImageGen，按动作分别生成；照片参考与提示词保存在 [prompts.json](prompts.json)。`raw-held/` 为生成原稿，`contact.png` 为打包后的动作总览，`layout.json` 为帧布局。

喝茶动作已按反馈补齐左手：六帧的左前臂与拳头均放在身前，出手帧不再藏到躯干背后。飞行茶杯独立绘制。

运行 `python3 tools/prepare_linbin.py` 打包正式图集、备用色、头像和独立特效；随后用 Godot 导入资源并运行 `tools/prepare_previews.gd` 更新轻量预览。全部动作使用 384×224 单元、脚底锚点 (192,208)，中文字由游戏字体绘制。

已通过 `tests/linbin.gd`（四技能、反射、倒计时、快照重演、24 场 CPU 对战）与 `tests/linbin_visual.gd`（432 帧边界、菜单、双朝向和减少闪光）。实机截图保存在 `build/qa/linbin_*.png`。
