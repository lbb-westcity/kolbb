# 版本管理与发布

仓库：`git@github.com:lbb-westcity/kolbb.git`。`main` 保存完成并验证的工作；正式版本使用 `v主版本.次版本.修订号` 标签。现有基线为 `v0.1.0`，不移动或覆盖已发布标签。

## 日常提交

在工作区干净时开始新功能；分支名按实际任务替换：

```sh
git switch main
git pull --ff-only origin main
git switch -c feat/your-feature
# 修改后检查差异，按实际文件路径暂存
git diff
git add path/to/changed-file
git diff --cached
git commit -m "feat: 描述完成的功能"
git push -u origin HEAD
```

一个提交解决一件事。功能用 `feat:`，修复用 `fix:`，文档用 `docs:`，构建用 `build:`。分支验证通过后合并到 `main`。不要强推共享分支；本机提交后推送到远端，才能形成异地副本。

源码、原始素材、`*.uid`、资源旁的 `*.import` 和 `export_presets.cfg` 纳入 Git。`.godot/`、`build/`、IDE 缓存、Python 缓存、私钥和本地凭据不提交。发行二进制上传 GitHub Releases。

## 版本号与发行

- 修复：`0.1.0 → 0.1.1`；新功能：`0.1.0 → 0.2.0`；重大不兼容变更提升主版本。
- 发布前同步 `project.godot` 的 `config/version` 与 `export_presets.cfg` 的 macOS `application/short_version`、`application/version` 和 Windows `application/file_version`、`application/product_version`。
- 将 `CHANGELOG.md` 的“未发布”条目归入新版本并注明日期。仅整理文档时可以保留在“未发布”，无需重发游戏。

在项目根目录执行：

```sh
bash tools/check.sh
python3 tools/build_wiki.py
python3 tests/wiki_test.py
bash tools/export.sh
git diff --check
```

Wiki 构建依赖见 [部署文档](DEPLOYMENT.md)。打包后按部署文档完成客户端与服务器验收。提交版本号和更新记录，确认 `git status --short` 没有输出，再为该提交打带说明的标签。以下 `0.1.1` 只是下次修复版示例：

```sh
git tag -a v0.1.1 -m "KOLBB 0.1.1"
git push origin main
git push origin v0.1.1
```

为该标签创建 GitHub Release 草稿，上传同一提交构建的三个发行包：`KOLBB-macOS.zip`、`KOLBB-Windows-x64.zip`、`KOLBB-Ubuntu-server.tar.gz`。在 GitHub Actions 手动运行 `Windows release smoke`，`tag` 输入该版本标签；通过后再发布。现有工作流只验证上传的 Windows 包，不会自动构建或发布。

## 查版本与回滚

```sh
git log --oneline -10
git describe --tags --always --dirty
# 在旁边创建旧版本的独立目录，不影响当前工作区
git worktree add --detach ../kolbb-v0.1.0 v0.1.0
```

撤销已共享的错误提交使用 `git revert <提交号>`，验证后推送，保留历史。服务器回滚按 [部署文档](DEPLOYMENT.md) 恢复对应发行包；Git 回滚本身不会更新线上服务。
