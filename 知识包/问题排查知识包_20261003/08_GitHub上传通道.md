# 08 · GitHub 上传通道

> 沉淀自 2026-10-03 排查会话。认证问题（H1）与大文件通道（H2）各一条。
> 本机仓库：liuchenljc/galaxy-watch7-shealth-on-xiaomi（私有，main 分支）；token 位置与环境快照见 09_附录_环境快照.md。

---

<a id="H1"></a>
## H1 · GitHub API 认证 Bad credentials

**影响范围**：所有 GitHub API 操作 ｜ **严重程度**：P2

### 现象
token 文件存在（330B），但 API 返回 `Bad credentials`。

### 报错关键信息

```json
{"message":"Bad credentials",...}
```

### 根因
token 文件的**前若干行是注释**（`# GitHub...` / `# 账号...` / `# 生成...` / `# 用途...` / `# 读取...`），
**真正的 token 在最后一行**（`ghp_` / `github_pat_` / `gho_` 开头，classic token 40 字符）。

直接把整个文件按行读出来传给 API，会把注释一起拼进 token → `Bad credentials`。
**这是"文件存在但认证失败"最常见的原因**，不是 token 过期。

### 快速定位
先看清 token 文件结构——注释占了前几行、token 在第几行：
```bash
grep -nE '^(ghp_|github_pat_|gho_)' <token文件>     # 打出 token 实际所在行号
head -3 <token文件>                                  # 确认开头是 # 注释
```

### 解决方案与操作步骤
只取 token 那一行，并去掉换行符（`\r\n`）：
```bash
TOKEN=$(grep -E '^(ghp_|github_pat_|gho_)' <token文件> | head -1 | tr -d '\r\n')
```

Windows Git Bash 下用命令替换写进变量：
```bash
TOKEN=$(grep -E '^(ghp_|github_pat_|gho_)' <token文件> | head -1 | tr -d '\r\n')
echo "${#TOKEN}"        # 打印长度，classic PAT 应为 40
```

> 建议在脚本里固化这个读法，别用 `cat` 或 `$(cat file)`。

### 验证
```bash
curl -H "Authorization: token $TOKEN" https://api.github.com/user
```
返回 `login`（本机账号：liuchenljc）。

### 预防
token 文件读法写进脚本；换 token 时保持『注释+token』格式或改为单行。

---

<a id="H2"></a>
## H2 · 大文件传不上 GitHub（Contents API 100MB 上限）

**影响范围**：项目备份与分发 ｜ **严重程度**：P2

### 现象
想备份 337MB 的三星健康 APK / 171MB 的插件，Contents API 传不了。

### 报错关键信息
无崩溃类报错：Contents API 对超过 **100MB** 的单文件直接拒绝，337MB APK / 171MB 插件均上传失败。

### 根因
Contents API（仓库文件）单文件上限 **100MB**。

### 快速定位
```bash
curl -s -o /dev/null -w '%{http_code}' https://uploads.github.com
```
本机实测返回 302 = 上传通道可用。

### 解决方案与操作步骤
改走 **Release 附件**（单文件上限 2GB）：
1. 创建 Release：`POST /repos/{o}/{r}/releases`（body 带 tag_name / name / body），响应里拿 release id；
2. 传附件：`POST uploads.github.com/repos/{o}/{r}/releases/{id}/assets?name=<文件名>`（二进制 body，`Content-Type: application/octet-stream`，长 timeout，如 1200s）。

### 验证
- `GET /repos/{o}/{r}/releases` 列出 assets；
- README 加 Release 入口。

### 实测记录
Release `v1.0-apps`（id 402468113）：17 个附件共 701MB 全部上传成功（三星四件套 / GeminiMan 双端 / 抗氧化启动器 / root 环境 / 刷机镜像 / 模块）。

### 预防
按体积分工：
- 文档 / 脚本 / 小模块 zip → 仓库文件（Contents API；PUT 已存在文件必须先 GET 拿 sha）；
- 大 APK / 镜像 → Release 附件。
