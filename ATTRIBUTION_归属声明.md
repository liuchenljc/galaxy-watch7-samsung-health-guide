# 归属与来源声明 / Attribution

> 本文件是这套方案里**两个模块的版权状态说明**。在复用、分发或改写任何东西之前，请先读完。

---

## 一、`shm_watch7_fix`（KSU 持久化模块）

**✅ 本项目原创，可自由使用。**

| 项 | 内容 |
|---|---|
| 包名 / id | `shm_watch7_fix` |
| 作者 | `liuchenljc` |
| 许可 | MIT |
| 构成 | `service.sh`（3005 B）、`system.prop`（67 B）、`module.prop`、`user_configure_fixed.db` |
| 第三方代码 | **无**。全部为本项目从零编写 |

`service.sh` 的注释里保留了完整的演进史（v1 → v5 的四个真实 bug 与修法），
这部分是第一手调试记录，可自由引用。

> ⚠️ 唯一的外部依赖：`user_configure_fixed.db` 是**本机（小米 14 / HyperOS 3.0.306）**
> 的 powerkeeper 状态快照。换机型**必须自建**，方法见
> [模块源码/shm_watch7_fix/README.md](模块源码/shm_watch7_fix/README.md)。

---

## 二、`spoof_module_v8_signed.apk`（LSPosed 伪装模块）

**⚠️ 这是【修改版】，不是原创。分发前请读完本节。**

| 项 | 内容 |
|---|---|
| 包名 | `com.arnold.spoofsamsung.Hook` |
| 原作者 | **未知** —— 原始 APK 内未包含任何作者、版权或许可声明 |
| 原许可 | **未知** —— 原始 APK 无 `LICENSE` 文件 |
| 获取方式 | 第三方渠道获得的**预编译 APK**，非从 GitHub 开源仓库获取 |
| 本项目改动 | 见下表 |

### 为什么原作者未知

对原始 APK 的取证结果：

```bash
# dex 里只有包名与 libxposed API 引用，无任何作者/许可字符串
unzip -p spoof_module_original.apk classes.dex | strings | grep -iE "author|license|copyright|github"
# → 无匹配

# resources.arsc 只有一句功能描述
# → 'Spoof Samsung device info for Galaxy Wearable apps.'
# → 'SpoofSamsung'
```

GitHub 检索结果同样为空：

| 检索 | 命中 |
|---|---|
| `search/code` `"com.arnold.spoofsamsung"` | 0 |
| `search/code` `spoofsamsung` | 9（全部无关：Vesper-OS 的 ghost_mode、nmap 脚本等） |
| `search/repositories` `spoofsamsung` | 0 |
| `search/repositories` `spoof samsung xposed` | 0 |

### 本项目所做的修改

| # | 修改 | 原因 |
|---|---|---|
| 1 | 新增第 4 个 hook：`SHM util/o.b0()` → `true` | 解锁 Ring 的 SLEEP 通道（睡眠呼吸暂停手机侧）。原版只有 3 个 hook |
| 2 | 修正三星健康中国版构建检查（KCB）的绕过路径 | 原版对 `com.sec.android.app.shealth` 的处理不完整 |
| 3 | 目标作用域从 `watchuniteplugin` 扩展到 `watch7plugin` | 原版只覆盖老款手表插件 |
| 4 | 重新打包与签名 | 改 smali 后必须重签。用 uber-apk-signer 内置 debug keystore |

完整改动证据见 [教程/kcb-bypass-hook.md](教程/kcb-bypass-hook.md) 与
`模块源码/smali_v8/com/arnold/spoofsamsung/Hook/SpoofSamsungModule.smali` 头部声明。

原包原样保留在私有仓库的 `artifacts/module/spoof_module_original.apk`。

### 许可状态与分发限制

> **无声明 = 保留所有权利。**
>
> 按《著作权法》默认规则，未声明许可的作品，他人不得修改或再分发。
> 反编译本身可能也违反原作品 EULA。
>
> 因此本仓库对这两件东西采取**最保守的处理**：
>
> | 内容 | 本公开包 | 私有仓库 |
> |---|---|---|
> | `spoof_module_v8_signed.apk`（预编译） | ❌ **不含** | ✅ 保留 |
> | `smali_v8/`（反编译源码） | ❌ **不含** | ✅ 保留 |
> | 原理说明与技术文档 | ✅ 含 | ✅ |
>
> **公开包只提供「原理 + 教程 + 本项目原创的 KSU 模块」。**
> 想要 LSPosed 模块的人，请自行按教程描述的 hook 点，从官方渠道或自己实现。

### 如果你是原作者

如果你就是 `com.arnold.spoofsamsung.Hook` 的作者，请联系我们，
本项目会：

1. 在所有文件中补上你的署名与许可声明
2. 把你的仓库地址、Issue 链接、联系方式写进 README
3. 把本项目做的 4 项修改整理成规范的 patch，供你合并

**联系方式**：见仓库 owner 的 GitHub 主页。

---

## 三、四个三星应用

`com.sec.android.app.shealth`、`com.samsung.android.shealthmonitor`、
`com.samsung.android.app.watchmanager`、`com.samsung.wearable.watch7plugin`

**均为三星版权，本项目不提供、不分发。** 请从 Galaxy Store 或你自己的三星设备获取。

本方案的前提是「**官方原版包 + 运行时打补丁**」——
换成任何第三方改版（签名不同），signature-level 权限与 sharedUserId 都会对不上，方案失效。

---

## 四、工具链

| 工具 | 许可 | 是否分发 |
|---|---|---|
| smali / baksmali 2.5.2 | Apache-2.0 | ❌ 读者自备 |
| uber-apk-signer 1.3.0 | MIT | ❌ 读者自备（私有仓库有） |
| JDK 17 | GPLv2+CE | ❌ 读者自备 |
| adb / fastboot | Apache-2.0 | ❌ 读者自备 |
| SukiSU Ultra | 见其仓库 | ❌ 读者自备 |
| Zygisk Next | GPL-3.0 | ❌ 读者自备 |
| Vector / LSPosed | GPL-3.0 | ❌ 读者自备 |
| KernelSU | GPL-3.0 | ❌ 读者自备 |

`工具/build_module.sh` 与 `工具/sanitize.py` 是本项目原创，随本包分发。

---

## 五、本项目

| 项 | 内容 |
|---|---|
| 教程与文档 | `liuchenljc` 原创 |
| KSU 模块 | `liuchenljc` 原创，MIT |
| 排查知识包 | `liuchenljc` 原创 |
| 辅助脚本 | `liuchenljc` 原创 |
| 协作 | 由 `liuchenljc` 与 AI 助手 LC 协作完成 |

**免责声明**：本项目仅用于技术学习与个人设备排障研究。
绕过厂商区域限制可能违反相关服务条款，请勿用于商业或侵害他人权益的用途。
血压 / 心电数据未经医疗认证，**不能作为诊断依据**。
