# MASTER · 全流程复刻手册（从零到跑通）

> **这是本仓库的总纲。** 其余 `docs/*.md` 都是专题深挖，本文档负责「照着做能跑通」。
> 最后更新：2026-10-02（对应模块 v8 / service.sh v5）
>
> 目标读者：想在**非三星手机 + root** 上让 Galaxy Watch7 完整跑通三星健康体系的人。

---

## 0. 目录

| 章节 | 内容 |
|---|---|
| [1](#1-前置条件) | 前置条件（硬件/软件/工具） |
| [2](#2-依赖版本表) | 依赖版本表 |
| [3](#3-执行顺序总览) | 执行顺序总览（9 步 + 4 个人工点） |
| [4](#4-分步详述) | 分步详述（含可直接复制的命令块） |
| [5](#5-配置项速查) | 配置项速查 |
| [6](#6-常见报错处理) | 常见报错处理 |
| [7](#7-目录说明) | 本仓库目录说明 |
| [8](#8-一键脚本) | 一键脚本用法 |
| [9](#9-四个功能的最终状态) | 四个功能的最终状态与验收判据 |
| [10](#10-已否决的路线) | 已否决的路线（别再踩） |

---

## 1. 前置条件

### 1.1 硬件

| 项 | 要求 | 备注 |
|---|---|---|
| 手机 | 任意 Android 8+ 非三星机型（实测小米 14 / Android 16） | 需 root |
| 手表 | Galaxy Watch4 或更高（**实测 SM-L310 = Watch7 44mm**） | 需 Wear OS 5.0+ |
| 蓝牙 | 手机与手表已配对，且 SAP（Samsung Accessory Protocol）链路可用 | 配对记录在手表端，不需重做 |

### 1.2 root 与框架

| 项 | 要求 | 校验命令 |
|---|---|---|
| root 方案 | KernelSU / SukiSU / Magisk 均可 | `adb shell su -c id` → 应含 `uid=0` |
| Zygisk | 开启（Zygisk Next 1.5.0 实测） | Magisk 设置里开启 |
| LSPosed | 2.2.0（Zygisk 版），管理器 = 模块内 manager.apk | `ls /data/adb/modules/` 应有 `zygisk_lsposed` |
| KSU 模块 | `shm_watch7_fix`（本仓库提供） | `ls /data/adb/modules/shm_watch7_fix` |

### 1.3 主机工具

| 工具 | 版本 | 用途 | 获取 |
|---|---|---|---|
| adb | platform-tools 任意新版 | 全程 | 官方 SDK platform-tools |
| Python | 3.8+ | 跑一键脚本、sqlite3 改库 | python.org |
| JDK | **17** | 跑 smali/签名器 | Adoptium Temurin 17 |
| smali / baksmali | **2.5.2** | 重建模块 dex | Maven Central |
| uber-apk-signer | **1.3.0** | APK 签名 | GitHub patrickfav |
| bash | 任意 | 跑 `tools/*.sh` | Windows 需 Git Bash |

> ⚠️ **本机注意（Windows）**：如果 adb 是从 PowerShell 调的，所有命令前加
> `export MSYS_NO_PATHCONV=1`（Git Bash）或用 `cmd` 包装，否则路径转换会破坏参数。

### 1.4 手机端 APK（必须是这些版本）

| 包 | 版本 | 说明 |
|---|---|---|
| `com.sec.android.app.shealth`（三星健康） | **7.00.6.011** | ≥6.27 即可；国行版走 `com.samsung.health.auth` 登录 |
| `com.samsung.android.shealthmonitor`（SHM） | **1.5.2.002** | 主目标 |
| `com.samsung.wearable.watch7plugin` | 随手表 | 提供手表能力信息 |
| `com.samsung.accessory` | 随手表 | SAP 传输层 |
| `com.samsung.android.app.watchmanager` | 随手表 | Galaxy Wearable |

### 1.5 必须人工完成的操作（共 4 处，脚本无法代劳）

> 根因：**MIUI 的系统会吞掉 `input tap`**（`input keyevent` 有效），所以任何需要点 UI 的步骤
> 脚本都点不了，必须你手点。

| # | 位置 | 动作 |
|---|---|---|
| ★1 | 手机 SHM「创建个人资料」页 | 填姓名(可空) + **出生日期(必须 ≥22 岁)** + 性别 → 保存 |
| 2 | 手机管家/设置 →「后台弹出界面」 | 放行 Galaxy Watch7 Manager、三星配件服务 |
| 3 | 三星健康 → 数据权限 | 三星健康监测器 = 全部允许 |
| 4 | 手表 → 三星健康监测器 | 睡眠呼吸暂停 → 开启（手机侧改不了） |

★1 是**总开关**，详见 §4.6。

---

## 2. 依赖版本表

| 组件 | 版本 | 变量/路径 | 备注 |
|---|---|---|---|
| 三星健康 | 7.00.6.011 | `com.sec.android.app.shealth` | |
| SHM | 1.5.2.002 | `com.samsung.android.shealthmonitor` | |
| 伪装模块 | **v8** | `artifacts/module/spoof_module_v8_signed.apk` | v8 新增 SA 通道 hook |
| 模块签名证书 | SHA256 `1e08a903aef9c3a721510b64ec764d01d3d094eb954161b62544ea8f187b5953` | uber-apk-signer 内置 debug keystore | **固定值**，同工具重签可直接覆盖装 |
| smali/baksmali | 2.5.2 | `apk/smali/*.jar` | 需 9 个 jar（见下） |
| uber-apk-signer | 1.3.0 | `apk/uber-apk-signer.jar` | ⚠️ `--out` 与 `--overwrite` 不能同时给 |
| JDK | 17 | `apk/jre/jdk-17.0.x-jre` | |
| Zygisk Next | 1.5.0 (843) | `/data/adb/modules/zygisksu` | |
| LSPosed | 2.2.0 (7854) | `/data/adb/modules/zygisk_lsposed` | Zygisk 版 |
| SukiSU Ultra | — | `com.sukisu.ultra` | 非 Magisk |
| ROM | MIUI/HyperOS 3.0.306 | 小米 14 (houji/23127PN0CC) | Android 16 |

**smali 依赖 jar 清单**（9 个，必须同版本）：
```
smali-2.5.2.jar  dexlib2-2.5.2.jar  util-2.5.2.jar
guava-27.1-android.jar  jcommander-1.64.jar  antlr-runtime-3.5.2.jar
stringtemplate-3.2.1.jar  antlr-3.5.2.jar  failureaccess-1.0.1.jar
```

---

## 3. 执行顺序总览

```
①  root 校验
      │
②  装伪装模块 v8  ──────────────┐
      │                          │  LSPosed 作用域需含 4 个包
③  装 KSU 模块 shm_watch7_fix    │  （首次装完需重启手机让 Zygisk 生效）
      │                          │
④  改 powerkeeper 省电库          │
      │                          │
⑤  设 CSC 地区属性 = XXV/VN      │
      │                          │
⑥  拉起 SAP 传输层 + 三星包  ◄───┘  ★ 新增，缺则手表消息发不出去
      │
⑦  ★【人工】SHM 创建个人资料 → 保存   ★ 总开关
      │
⑧  拉起 SHM 验证
      │
⑨  验收：血压 / 心电图 / 睡眠呼吸暂停
```

**★ 三个必须记住的「时序陷阱」**

1. **③ 之后必须重启手机一次** —— KSU 模块的 `service.sh` 由 Zygisk 在开机时拉起。
2. **⑦ 之前必须先做完 ⑥** —— 否则 SetupActivity 拉起来也不会有任何交互。
3. **② 的 LSPosed 作用域**要在模块管理器里配好（见 §4.2），否则 ⑦ 的入口改道会失败。

---

## 4. 分步详述

### 4.1 ① root 校验

**前置**：手机已 root，USB 已连接（`adb devices` 能看到）。

```bash
adb devices
adb shell su -c id          # 应输出 uid=0(root) ... context=u:r:ksu:s0
```

**常见报错**
- `Permission denied` / `command not found` → root 没生效，检查 KernelSU 是否已激活
- `device 'xxx' not found` → adb daemon 掉了，见 §6.3

---

### 4.2 ② 安装伪装模块 v8

**前置**：LSPosed 已安装并启用。

```bash
# 仓库根目录下
adb install -r artifacts/module/spoof_module_v8_signed.apk
```

> ✅ **不需要先卸载旧版**。uber-apk-signer 用的是内置 debug keystore，证书固定，
> 同工具重签出来的包证书一致，可以直接覆盖装，LSPosed 作用域配置不会丢。
> 想确认的话：
> ```bash
> java -jar apk/uber-apk-signer.jar --apks artifacts/module/spoof_module_v8_signed.apk --onlyVerify
> adb shell "su -c 'cp \$(pm path com.arnold.spoofsamsung.Hook | sed s/package://) /data/local/tmp/m.apk'"
> adb pull /data/local/tmp/m.apk .
> java -jar apk/uber-apk-signer.jar --apks m.apk --onlyVerify   # 两者 SHA256 应一致
> ```

**装完必做**：LSPosed 作用域里确认包含这 4 个包
```
com.samsung.wearable.watch7plugin
com.samsung.wearable.watchuniteplugin
com.sec.android.app.shealth
com.samsung.android.shealthmonitor
```

**然后 force-stop 目标应用即可生效，不需要重启手机**（LSPosed 每次进程启动都重读模块 dex）：
```bash
adb shell "su -c 'am force-stop com.samsung.android.shealthmonitor'"
```

**验证 hook 是否注册**（去 LSPosed 日志，不要看 logcat）：
```bash
adb shell "su -c 'grep -i arnold /data/adb/lspd/log/modules_*.log | tail -20'"
```
应看到 4 条：
```
HOOK REGISTERED: shealthmonitor.mainactivity
HOOK REGISTERED: shealthmonitor.country (network/sim iso -> vn)
HOOK REGISTERED: shealthmonitor.sa.enable (util.o.b0 -> true, unlocks Ring SLEEP channel)
HOOK REGISTERED: shealthmonitor.china.build   # 仅三星健康进程
```

---

### 4.3 ③ 安装 KSU 持久化模块

**前置**：② 完成。

一键脚本会做这件事；手动做的话：

```bash
K=/data/adb/modules/shm_watch7_fix
adb shell "su -c 'mkdir -p $K'"
adb push artifacts/shm_watch7_fix/module.prop            $K/
adb push artifacts/shm_watch7_fix/system.prop            $K/
adb push artifacts/shm_watch7_fix/service.sh             $K/
adb push artifacts/shm_watch7_fix/user_configure_fixed.db $K/
adb shell "su -c 'chmod 755 $K/service.sh; chown -R root:root $K'"
```

**内容说明**

| 文件 | 作用 |
|---|---|
| `system.prop` | 用 `resetprop` 设 `ro.csc.sales_code=XXV` / `ro.csc.countryiso_code=VN` / `ro.csc.iso_code=VN` |
| `service.sh` | **v5**：开机常驻（`setsid`），每 300s 检查一次 powerkeeper，回滚就恢复快照；并守护 SAP 进程 |
| `user_configure_fixed.db` | MIUI powerkeeper 省电库快照，8 个包为 `noRestrict` |
| `module.prop` | 模块元信息 |

**⚠️ 必须重启手机一次**，让 Zygisk 拉起 `service.sh`。重启后验证：
```bash
adb shell "su -c 'ps -A -o PID,PPID,ARGS | grep shm_watch7 | grep -v grep'"
# 期望：<pid>  1  sh /data/adb/modules/shm_watch7_fix/service.sh
#        ^ PPID=1 表示已脱离会话，不会被回收
adb shell "su -c 'cat /data/adb/modules/shm_watch7_fix/self_heal.log'"
```

> 🔧 **service.sh 演进史（别退回老版本）**
> | 版本 | 写法 | 结果 |
> |---|---|---|
> | v1 | `( ... ) &` 后台子 shell | ❌ KSU 父脚本退出后子进程被回收，**开机 6h45m 零次执行** |
> | v2 | 前台死循环 | ❌ 判据依赖 `sqlite3` 命令，手机根本没这命令 |
> | v3 | 文件大小做指纹 | ❌ 差 4096B < 4% 阈值，漏判 |
> | v4 | `setsid` + `noRestrict` 计数 | ⚠️ 判据可靠，但 900s 间隔与云端回滚周期(~15min)同频，一半时间 SAP 是被限的 |
> | **v5** | 300s 间隔 + `ensure_sap()` | ✅ 当前版本 |

---

### 4.4 ④ 改 powerkeeper 省电库

**前置**：③ 完成。

MIUI 的 powerkeeper 会把三星相关包改成 `miuiAuto`，导致它们被后台冻结。**这是「手表有数据但手机没反应」的根因。**

```bash
DB=/data/data/com.miui.powerkeeper/databases/user_configure.db
adb shell "su -c 'am force-stop com.miui.powerkeeper'"
adb push artifacts/shm_watch7_fix/user_configure_fixed.db /data/local/tmp/uc.db
adb shell "su -c 'cp /data/local/tmp/uc.db $DB; chown system:system $DB; chmod 660 $DB; rm -f $DB-journal'"
adb shell "su -c 'am force-stop com.miui.powerkeeper'"
```

**验证**：
```bash
adb shell "su -c 'grep -a -o noRestrict $DB | wc -l'"   # 期望 >= 8，回滚态是 5
```

> ⚠️ **云端会周期性回滚**（实测约 5–15 分钟一次）。这就是 `service.sh` 存在的原因。
> 若发现长期是 5，把 `service.sh` 的 `INTERVAL=300` 调到 `180`。

---

### 4.5 ⑤ 设 CSC 地区属性

**前置**：③ 完成（`system.prop` 会在开机时自动设，这里是手动补设 + 验证）。

```bash
for kv in "ro.csc.sales_code XXV" "ro.csc.countryiso_code VN" "ro.csc.iso_code VN"; do
  set -- $kv
  adb shell "su -c '/data/adb/ksu/bin/resetprop $1 $2 2>/dev/null || resetprop $1 $2'"
done
adb shell getprop ro.csc.sales_code        # 期望 XXV
adb shell getprop ro.csc.countryiso_code   # 期望 VN
```

> 为什么是 VN：SHM 内部用「SIM 国家码」判功能支持度。`TelephonyManager.getSimCountryIso()`
> 被模块 hook 成 `vn`，SHM 会认为处于越南 —— 这是目前唯一能让 BP/ECG/IHRN 三个通道放行的取值。
> 注意：**SA（睡眠呼吸暂停）即使在 VN 也被构建期禁用**，见 §9。

---

### 4.6 ⑥ 拉起 SAP 传输层 + 三星包 ★

**前置**：④ ⑤ 完成（powerkeeper 必须是 noRestrict，否则拉起来也会被杀）。

```bash
# 1) 手表插件（提供手表能力信息）
adb shell "su -c 'am start -n com.samsung.wearable.watch7plugin/com.samsung.android.waterplugin.activity.HMLaunchActivity'"
# 2) Galaxy Wearable
adb shell "su -c 'am start -n com.samsung.android.app.watchmanager/com.samsung.android.app.watchmanager.setupwizard.SetupWizardWelcomeActivity'"
# 3) SAP 传输层（核心）
adb shell "su -c 'am broadcast -a android.accessory.device.action.CONNECT -n com.samsung.accessory/.receivers.SAFrameworkStartTriggerReceiver'"
sleep 4
# 验证
adb shell "ps -A | grep -E 'samsung.accessory|watch7plugin|watchmanager|shealthmonitor'"
```

> 🔧 **两个必须知道的点**
> 1. **改 `noRestrict` 不会自动复活进程** —— 必须显式广播。`com.samsung.accessory`
>    没有任何 launcher activity，只能靠 `SAFrameworkStartTriggerReceiver` 触发。
> 2. **`exported=0` 的 activity 必须用 root 拉起** —— Android 16 强制校验，
>    `adb shell am start`（shell uid）会报 `SecurityException: ... not exported from uid ...`，
>    必须 `su -c`。

> 📌 如果 `watch7plugin` / `watchmanager` 死了，SHM 会误报
> **「没有找到兼容的手表」+ [重试]** —— 点重试没用，因为重试只是重跑协商流程。

---

### 4.7 ⑦ ★【人工】SHM 创建个人资料 —— 三功能总开关

**前置**：⑥ 完成。

这一步是**整个项目最关键的一步**。血压、心电图、睡眠呼吸暂停三个功能共用一个总开关：

```
SHM pref:  shealth_monitor_base_app_setup_init      （默认 false）
   ├─ 被谁写？  只有「创建个人资料」页的保存按钮（ld/e0.smali 的 :cond_5e 分支）
   ├─ 谁读它？  ActionRequestActivity（血压 deep-link 入口）
   │            SHealthMonitorSetupActivity.synchronizeTnc()（ECG 条款广播）
   └─ 为什么写不上？ LSPosed 模块把 SHM 入口改道到首页，绕过了 Setup→ProfileEdit 链
```

**拉起初始化流程**：
```bash
adb shell "su -c 'am start -n com.samsung.android.shealthmonitor/com.samsung.android.shealthmonitor.home.ui.activity.SHealthMonitorSetupActivity'"
```

**【必须手点】** 屏幕上会出现「创建个人资料」页（条款若已同意会自动跳过）：

```
┌─────────────────────────────────────────┐
│  首先，让我们确认此功能是否适合您          │
│  医生是否曾诊断您患有睡眠呼吸暂停？        │
│   ○ 姓名                                   │
│   ○ 姓                                    │
│   [选择出生日期]   ← 出生日期必须 ≥22 岁   │
│   ○ 男  ○ 女                               │
│              [ 保存 ]                     │
└─────────────────────────────────────────┘
```

> ⚠️ **出生日期必须 ≥22 岁**。`util/o.X(22)` 是硬门禁，未满 22 岁时
> 血压 deep-link 会被跳过（`isValidAge=false`），ECG 也有年龄门（SA1.0 = 22 岁）。

**保存后验证**（这一条最直接）：
```bash
adb shell "su -c 'grep -c setup_init /data/data/com.samsung.android.shealthmonitor/shared_prefs/permanent_shared_preferences_main.xml'"
# 期望输出 1（有该键）

# 端到端验证：发一条血压 deep-link，看是否被接收
adb logcat -c
adb shell "am start -n com.samsung.android.shealthmonitor/com.samsung.android.shealthmonitor.ui.activity.ActionRequestActivity -d 'shealthmonitor://shealthmonitor.samsung.com/actionRequest?type=BP&action=BP_Measure'"
sleep 3
adb logcat -d | grep -E "parseIntent|BloodPressureController"
```
**期望看到**：
```
[parseIntent] isAppInitialized = true, isValidAge = true
[BloodPressureController] [doAction] DO_ACTION_MEASURE_BP_ON_THE_WATCH
[Node] send(). connectionState=CONNECTED. body={"action":"do_calibration",...} seq=16
[WSM] WSM_I [enc]
```
若仍是 `isAppInitialized = false` → 这一步没成功，回到本节重做。

**副作用（顺带修好的东西）**：
- `synchronizeTnc()` 随之执行 → `shealth_monitor_ecg_tnc_complete` 落盘 → **心电图握手解锁**
- `DATA_PERMISSION_STATE` 获授 → SHM 可以往三星健康写数据
- `shealth_monitor_base_user_profile` 落盘 → 年龄门有真实数据

---

### 4.8 ⑧ 启动 SHM 验证

```bash
adb shell "su -c 'am force-stop com.samsung.android.shealthmonitor'"
adb shell "su -c 'am start -n com.samsung.android.shealthmonitor/com.samsung.android.shealthmonitor.home.ui.activity.SHealthMonitorMainActivity'"
```

**界面应出现**（底部三个 tab）：睡眠呼吸暂停 / 血压 / 心电图

**数据权限页**（确认 SHM 能写三星健康）：
```bash
adb shell "su -c 'am start -n com.samsung.android.shealthmonitor/com.samsung.android.shealthmonitor.home.ui.activity.SHealthMonitorDataPermissionActivity'"
# 应显示「三星健康 · 上次同步时间：<近期时间>」
```

---

### 4.9 ⑨ 验收

见 §9。

---

## 5. 配置项速查

### 5.1 地区相关

| 项 | 值 | 作用 | 改错的后果 |
|---|---|---|---|
| `ro.csc.sales_code` | `XXV` | 地区销售码 | SHM 判功能支持度 |
| `ro.csc.countryiso_code` | `VN` | 国家码 | 同上 |
| `ro.csc.iso_code` | `VN` | 同上 | 同上 |
| `getSimCountryIso()` hook | `vn` | SHM 内部读 | 同上 |

**改其他地区行不行？** BP/ECG/IHRN 三个通道在多个国家可用（SHM 里有 85 国 SIM 白名单 `util/o.m`），
但 **SA（睡眠呼吸暂停）无论如何都不行** —— 它被编译期禁用，见 §9.2。

### 5.2 保活相关（`artifacts/shm_watch7_fix/service.sh`）

| 变量 | 默认 | 含义 | 调整建议 |
|---|---|---|---|
| `INTERVAL` | `300` | 自愈轮询间隔（秒） | 云端回滚频繁可降到 `180` |
| `EXPECT_NO_RESTRAINT` | `8` | 健康态 noRestrict 出现次数 | 换 ROM 需重算（用 `grep -c` 统计） |
| `DB` | `/data/data/com.miui.powerkeeper/databases/user_configure.db` | 目标库 | 非 MIUI 需改 |
| `SNAP` | `$MODDIR/user_configure_fixed.db` | 快照 | **每台机不同，需自建** |

**自建快照的方法**（因为每台机的 powerkeeper 库内容不同）：
```bash
# 1) 先手工把目标包在「手机管家 → 省电策略」里设为"无限制"
# 2) 然后导出
adb shell "su -c 'cp /data/data/com.miui.powerkeeper/databases/user_configure.db /data/local/tmp/uc.db; chmod 666 /data/local/tmp/uc.db'"
adb pull /data/local/tmp/uc.db ./user_configure_fixed.db
```

### 5.3 模块作用域（LSPosed）

必须包含：
```
com.samsung.wearable.watch7plugin     # 手表能力伪装 + SA hook
com.samsung.wearable.watchuniteplugin  # 手表能力伪装
com.sec.android.app.shealth            # KCB 中国版构建 hook
com.samsung.android.shealthmonitor     # 入口改道 + 国家 hook + SA hook
```

---

## 6. 常见报错处理

### 6.1 bootloop（开不了机）

> ⚠️ **永久封存**：往 `/system/etc/permissions/` 塞伪造 `<library>` XML（想补 `android.*` 框架类）**必 bootloop**，已中过一次。

**症状**：重启后卡在开机动画/黑屏，进 ADB 后 `adb shell` 无响应。

**急救**：
```bash
adb kill-server && adb start-server
adb wait-for-device
adb shell "ls /data/adb/modules/"        # 哪个模块出问题就临时 mv 走
adb shell "su -c 'mv /data/adb/modules/<问题模块> /data/local/tmp/'"
adb reboot
```
Zygisk 模块全部在 `/data/adb/modules/`，**临时移走任意一个都能救砖**（会失去对应功能但能开机）。

### 6.2 `pkill` 把 adb 自己杀了

```bash
# ❌ 危险：会匹配到自身命令行 → 杀掉自己的 shell → adb 立刻掉线
adb shell "su -c 'pkill -f service.sh'"

# ✅ 用不自匹配的模式
adb shell "su -c 'pkill -f \"servic[e].sh\"'"
```

### 6.3 adb daemon 反复自崩

**症状**：每条命令都报 `daemon not running; starting now` + `device not found`。

**恢复**：
```bash
adb kill-server; sleep 3
adb start-server; sleep 6
```
**关键**：把「检查在线」和「执行」放进**同一条命令**，外面套重试循环：
```bash
A=/path/to/adb.exe
for i in 1 2 3 4 5 6; do
  if $A devices 2>/dev/null | grep -q "<SERIAL>"; then
    $A -s <SERIAL> shell "echo ok" && break
  fi
  $A start-server >/dev/null 2>&1; sleep 3
done
```

### 6.4 SHM 报「没有找到兼容的手表」

**三个可能，按顺序排查**：

| 检查 | 命令 | 判读 |
|---|---|---|
| ① 手表插件死了 | `adb shell "ps -A \| grep watch7plugin"` | 空 → 拉起（§4.6） |
| ② SAP 传输层死了 | `adb shell "ps -A \| grep samsung.accessory"` | 空 → 拉起（§4.6） |
| ③ powerkeeper 回滚了 | `adb shell "su -c 'grep -a -o noRestrict /data/data/com.miui.powerkeeper/databases/user_configure.db \| wc -l'"` | < 8 → 等 service.sh 自愈或手动恢复（§4.4） |

若三者都正常但仍报错 → 看 §9.2（构建期禁用）。

### 6.5 血压 deep-link 无反应

```bash
adb logcat -c
adb shell "am start -n com.samsung.android.shealthmonitor/com.samsung.android.shealthmonitor.ui.activity.ActionRequestActivity -d 'shealthmonitor://shealthmonitor.samsung.com/actionRequest?type=BP&action=BP_Measure'"
sleep 3 && adb logcat -d | grep -E "parseIntent|BloodPressureController"
```
| 看到什么 | 含义 | 怎么办 |
|---|---|---|
| `isAppInitialized = false` | 总开关没写上 | 重做 §4.7 |
| `isValidAge = false` | 资料页生日 <22 岁 | 重做 §4.7，改大生日 |
| `doAction` 出现但无 `connectionState=CONNECTED` | SAP 链路断 | 重做 §4.6 |

### 6.6 签名冲突（`INSTALL_FAILED_UPDATE_INCOMPATIBLE`）

```bash
# 原因：模块是用别的 keystore 签的
# 解决：卸载后重装（会丢 LSPosed 作用域配置，需重配）
adb uninstall com.arnold.spoofsamsung.Hook
adb install artifacts/module/spoof_module_v8_signed.apk
```
> 正常情况下**不会遇到** —— 本仓库所有模块包都用 uber-apk-signer 内置 debug keystore 签，证书固定。

### 6.7 读不出加密的 prefs / 数据库

三星健康和 SHM 的关键数据都用 **Android Keystore 持有的 AES-GCM 密钥**加密
（SHM 的 tag = `S HealthMonitor - DataKeyUtil`，格式 `Base64(iv)#Base64(ct)`）。
**密钥不可离线提取**。

替代判据（用行为观测，不用读值）：
| 想确认 | 改用什么 |
|---|---|
| setup_init | logcat `[parseIntent] isAppInitialized` |
| 血压是否到手机 | 三星健康 prefs `tracker_bloodpressure_timestamp`（见 §9.1） |
| SA 是否激活 | logcat `SleepApneaCard activationStateObserver.onChange(...)` |
| powerkeeper 状态 | `grep -a -o noRestrict ... | wc -l`（这库不加密） |

### 6.8 Lsposed 里改了东西但不生效

LSPosed 在**进程启动时**读取模块 dex。所以：
```bash
adb shell "su -c 'am force-stop com.samsung.android.shealthmonitor'"   # 只需重启目标应用
```
**通常不需要重启手机**。只有改了 `/data/adb/modules/` 里的东西（KSU 模块）才需要重启。

### 6.9 写 adb 判据时的三个经典假阴性（都踩过）

这三条会让你误判"功能没通"，但功能其实是好的：

**① `grep -c` 只输出数字，不能用关键字判断存在性**
```bash
# ❌ 输出是 "1"，不含 "setup_init" 三个字 → 恒 False
out = adb shell "grep -c setup_init /path/prefs.xml"
ok = "setup_init" in out

# ✅ 看计数
n = int(out.strip().splitlines()[-1])
ok = n > 0
```

**② 用 logcat 搜一个字符串，会命中你自己**
```bash
# ❌ 这条命令的字符串本身被 logcat 记成 adbd 日志 → 永远 >=1
adb shell "logcat -d | grep -c 'not supported in'"

# ✅ 用字符类打断，且限定 tag
adb shell "logcat -d -t 300 | grep 'S HealthMonitor - Rin[g]' | grep -c 'not supported i[n]'"
```
`-t 300` 限定最近 300 行，避免几小时前的历史日志污染。

**③ `su -c '...'` 里不能嵌套单引号**
```python
# sh() 是这样包装的：adb shell "su -c '<cmd>'"
# ❌ cmd 里再出现单引号 → shell 把命令拆散，结果不可预测（本次真的踩了）
sh(f"grep -ahoE 'name=.\"tracker\" value=.\"[0-9]*' file")

# ✅ 正则里避开单引号，用字符类跨越引号
sh(f"grep -ahoE tracker_bloodpressure_timestamp[^0-9]*[0-9]+ file")
```

**④ 顺带**：血压的键名有三种写法，正则要写 `blood[_]?pressure`
```
tracker_bloodpressure_timestamp            ← 无下划线（SHM 走 Health Data API 写的）
tracker_bloodpressure_last_timestamp       ← 无下划线
tracker_blood_pressure_latest_data_timestamp ← 有下划线
tracker_blood_pressure_count               ← 有下划线
```

---

## 7. 目录说明

```
.
├── README.md                    项目总览 + 文档索引
├── MASTER_全流程.md              ← 本文档，全流程总纲
│
├── oneclick/                    【一键复刻包】第三方免 AI 版
│   ├── 一键复刻.bat              Windows 双击入口
│   ├── 一键复刻.py               8 步自动化 + --verify 体检
│   ├── README_必读.md            4 项人工步骤说明 + 故障排查
│   ├── assets/
│   │   └── spoof_v8.apk          伪装模块 v8
│   └── ksu_module/              KSU 持久化模块（会被推到 /data/adb/modules/）
│       ├── module.prop
│       ├── system.prop           CSC 地区属性
│       ├── service.sh            v5：保活自愈 + SAP 守护
│       └── user_configure_fixed.db  powerkeeper 快照（每台机需自建）
│
├── artifacts/                   【产物】
│   ├── module/
│   │   ├── spoof_module_original.apk    原始模块（重建时作 APK 外壳）
│   │   ├── spoof_module_v7_signed.apk   v7（无 SA hook，仅历史留档）
│   │   ├── spoof_module_v8_signed.apk   v8 ★ 当前推荐
│   │   └── smali_v8/                    v8 完整 smali 源码（11 个文件）
│   └── shm_watch7_fix/          KSU 模块源文件
│       ├── module.prop / system.prop
│       ├── service.sh                  = service_v5.sh（当前）
│       ├── service_v5.sh               v5 原件（留档）
│       └── user_configure_fixed.db
│
├── docs/                        【文档】按需深挖
│   ├── MASTER_全流程.md          ★ 全流程总纲（本文档），建议先读这份
│   ├── SHM_Watch7_可复刻手册.md
│   ├── kcb-bypass-hook.md              OOBE KCB 绕过
│   ├── miui-powerkeeper-balkill.md     省电拦截根因
│   ├── deepdive-bp-timeout-ecg-deadlock.md  smali 深挖
│   ├── 三功能问题分析_20261002.md       血压/心电图/AGEs
│   ├── 睡眠呼吸暂停专项_20261002.md     SA 专项
│   ├── antioxidant-ages-gating.md       抗氧化 vs AGEs
│   ├── sleep-monitoring-autonomy.md
│   ├── thirdparty-apk-phone-entry.md
│   ├── handover.md / handover-zcode-20261001.md
│   └── ...
│
└── tools/                       【工具】
    ├── build_module.sh           从 smali 重建+签名模块
    ├── shm_watch7_doctor.sh      链路体检 + --fix 一键修复
    ├── axml_scan.py              APK 清单/资源扫描
    └── arsc_strings.py           资源表字符串提取
```

---

## 8. 一键脚本

```bash
cd oneclick
python 一键复刻.py            # 执行 8 步自动化
python 一键复刻.py --verify   # 只读体检
```

Windows 用户双击 `一键复刻.bat`。

**`--verify` 的 9 项体检**（本机实测 9/9 通过）：
```
[OK] 伪装模块已安装
[OK] 持久化模块已安装
[OK] CSC 地区属性 = XXV/VN
[OK] powerkeeper noRestrict 数（期望 ≥8）
[OK] SAP 传输层 + 三星包进程存活
[OK] setup_init 总开关（三功能必需）
[OK] ECG 条款握手前提 tnc_complete
[OK] SA 通道（v8 hook 生效判据）
[OK] 血压已回写三星健康（并打印 timestamp / systolic / diastolic / count）
```

**脚本做的**（8 次调用）：① root 校验 → ② 装模块 v8 → ③ 装 KSU 模块 → ④ 改 powerkeeper
→ ⑤ 设 CSC → ⑥ 拉起 SAP/三星包 → ⑦**拉起** SetupActivity（不含保存）→ ⑧ 验证

**脚本做不了的**：★1（资料页的"保存"那一下）、以及 §1.5 表里另外 3 个人工项

> ⚠️ 脚本里的 `ADB_CANDIDATES` 是硬编码路径，含作者本机路径。
> 换机器请把 `adb.exe` 放到 `oneclick/` 目录下（脚本第一个候选就是它），
> 或改 `ADB_CANDIDATES`。

---

## 9. 四个功能的最终状态

> **2026-10-02 用户实机验证结论：除睡眠呼吸暂停外，全部功能可用。**

| 功能 | 状态 | 备注 |
|---|---|---|
| 血压 | ✅ **全通** | 手机指挥手表 + 回写三星健康 |
| 心电图 | ✅ **全通** | 需在手表端发起 |
| AGEs | ✅ 数据正常上传 | 指数随连续佩戴累积 |
| 抗氧化 | ✅ 原生 61 分 | 不需要第三方 APK（见 §9.5） |
| 常规健康 | ✅ **全通** | 步数/睡眠/心率/体成分 |
| 睡眠呼吸暂停 | ❌ **不可用** | 手表端 SHM 构建期禁用 |

### 9.1 ✅ 血压 —— 已闭环

**全链路**：手表袖带测量 → SAP → 手机 SHM → Health Data API → 三星健康

**验收判据**（**不要用 `tracker_bloodpressure_accessory_data_count`** —— 那是"配饰同步"通道的计数，
SHM 走 Health Data API 不更新它，会误判）：
```bash
adb shell "su -c 'grep -ahoE \"name=.[a-z_0-9.]*blood_pressure[a-z_0-9.]*. value=.[0-9]*\" /data/data/com.sec.android.app.shealth/shared_prefs/*.xml' | sort -u"
```
期望：
```
tracker_bloodpressure_timestamp = <毫秒时间戳>       ← 最新一条记录的时间
tracker_bloodpressure_systolic = 118
tracker_bloodpressure_diastolic = 72
tracker_blood_pressure_count = 2
```

**已知永久限制**：三星健康 App 内**永远没有**主动测血压的入口（只有数据接收登记键）。
这是三星的产品设计，与手机品牌无关 —— 手机只负责"指挥手表 + 接收数据"。

**校准**：袖带血压计校准一次，28 天内有效。校准数据会记到手表端
（`fc/c.smali` 里有 `need_to_recal` / `calibration_time`）。
若看到 `bp_module_disable_state` 超时 —— **三星自己说了这是正常现象**，代码注释原文：
> "Wear won't send `bp_module_disable_state` response message to phone. So response timeout
> will be detected, but it is a normal operation. Don't worry."

### 9.2 ❌ 睡眠呼吸暂停（SA）—— 构建期禁用，已尝试绕过但卡在手表端

**手机端已修**（v8 模块 hook `util/o.b0()` → `true`）：
```
修复前：getRestrictionAgeBeforeOnboarding() = 22. Because it is SA1.0 phone
        Ring: skip onNodeChanged() because this channel(SLEEP) is not supported in VN
修复后：getRestrictionAgeBeforeOnboarding() = 18. Because it is SA2.0 phone
        onNodeChanged(). SLEEP, 502bd5e69c65d...
        Got feature version: 2
```

**根因**：
```smali
; outA/com/samsung/android/shealthmonitor/util/o.smali  的 <clinit>
const/4 v0, 0x0
new-array v0, v0, [Ljava/lang/String;     ; ← 长度 0
sput-object v0, o->n:[Ljava/lang/String;  ; ← o.n = String[0]（空数组）
```
`o.b0()` = 检查当前国家码是否在这个**空数组**里 → **恒 false**
→ `fk/h.n(RingChannel.SLEEP)` = `if (ch==SLEEP) return b0()` → **恒 false**
→ Ring 跳过 SLEEP 通道 → 界面误报「没有找到兼容的手表」。

**剩余阻塞（无法在手机侧解决）**：手表端没有为 SA 通道注册节点。
```
BP   : CONNECTING → 502bd5e69c65d...  CONNECTED
ECG  : CONNECTING → 502bd5e69c65d...  CONNECTED
IHRN : CONNECTING → 502bd5e69c65d...  CONNECTED
SLEEP: CONNECTING → （空）              DISCONNECTED   ← 节点 id 从未分配
```
`Got feature version: 2` 是**手表端**通过 `SELECTED_FEATURE_VERSION` 上报的，
说明手表端固件支持 SA2.0；但手表端 SHM **本身没有「睡眠呼吸暂停」这个菜单**
（用户 2026-10-02 实测确认）→ **手表端 SHM 也有同样的编译期禁用**。

手表端 APK 无法从手机侧修改，且 Watch7 无 root / 无法上 LSPosed。
**结论：SA 在这台设备组合上不可用。**

### 9.3 ✅ 心电图 —— 已闭环

```bash
adb shell "su -c 'ls -la /data/data/com.samsung.android.shealthmonitor/databases/RoomSHealthMonitorEcg.db'"
# 期望：mtime = 今天，size 明显大于 28,672（空库基线）
```
实测 167,936 B（6 倍）。

**操作**：**必须在手表上发起**（手机端设计上没有遥控入口，`ACTION_TYPE` 8 项枚举里没有 ECG）。
手表 → 三星健康监测器 → 心电图 → 按住主屏幕按钮 30 秒。

**已知永久限制**：同上，三星健康 App 内没有 ECG 测量入口。

### 9.4 ⏳ AGEs（糖基化终末产物）—— 数据在传，指数未达门槛

**实测**：`history_database.db` 的 `sync_history` 里有 **7 条**
`com.samsung.health.advanced_glycation_endproduct.raw`（10-01 凌晨 3 条、01:50、08:12、10-02 10:11 两条），
**全部 Success、来源 Wearable**。说明手表端一直在正常上传。

但**指数型**（非 `.raw`）的记录 **0 条** → 指数还没生成。

**怎么办**：
1. 三星健康首页打开「生物年龄 / 糖基化终末产物」磁贴（`tracker.age`，已存在但从未被访问过）
2. **连续佩戴入睡 3–5 晚**（必须戴表入睡）

### 9.5 🎁 抗氧化指数实测可用（61 分），且**不需要第三方 APK**

交接文档曾写「Watch7 硬件不支持抗氧化」，**已被实测证伪**：
```
ANTIOXIDANT_RECENT_SCORE = 61
ANTIOXIDANT_7_DAYS_SCORE = [-1,-1,-1,-1,-1,-1,61]
sync_history: com.samsung.health.antioxidant  10-01 09:04:39 Success cnt=1 来源=Wearable
              模块 = WEARABLE_REQUEST_DATA
message_history: sender   = com.samsung.wear.app.shealth.antioxidant
                receiver = com.samsung.mobile.app.shealth.antioxidant
                device_id= <DEVICE_ID>            （11 条消息往来）
```
`ANTIOXIDANT_IS_SUPPORTED_WEARABLE_CONNECTED_EARLIER = false` 只反映三星健康对
「当前连接设备型号是否在官方名单」的判断，**与实际测量能力无关**。
**不要为了抗氧化去刷国际固件或 root 手表。**

#### 那个第三方 APK 是纯图标壳（重要，别误解）

侧载链：`com.flyfishstudio.wearosbox`（WearOS 工具箱，手机端）
→ 装到手表 → `com.skya.antioxidantsindex`（"Antioxidants Index (Galaxy Watch 7).apk"）

反编译后**全文只有一句**：
```java
startActivity(new ComponentName("com.samsung.android.wear.shealth",
        "...app.antioxidant.AntioxidantActivity"));
```

| | |
|---|---|
| 它做什么 | 把三星健康**原生**的抗氧化测量界面拉起来（等于一个桌面图标） |
| 它不做什么 | **没有任何测量、采样、计分、蓝牙传输代码** |
| 真正的测量者 | 手表端 `com.samsung.wear.app.shealth.antioxidant`（原生模块） |
| 卸载它 | **不影响功能**，只是少个快捷图标 |

> 依据：数据链路两条独立证据（`sync_history` 的 `WEARABLE_REQUEST_DATA` +
> `message_history` 的 sender/receiver 均为 `com.samsung.*.health.antioxidant`），
> 都不经过任何第三方包名。

---

## 10. 已否决的路线（别再踩）

| 路线 | 结论 | 原因 |
|---|---|---|
| 往 `/system/etc/permissions/` 塞伪造 `<library>` XML | ❌ **必 bootloop** | 已中过一次 |
| 用 LSPosed 补 `android.*` 框架类（如 `SemSystemProperties`） | ❌ 不可能 | 框架类在 boot classpath，LSPosed 作用域管不到 |
| KnoxPatch 系修三星账号框架 | ❌ 无效 | 前提是三星设备；小米上 `class_defs` 未定义 `SemSystemProperties` |
| 安装三星账号框架 `com.osp.app.signin` | ❌ 崩溃 | 缺 `SemSystemProperties`；改用 `com.samsung.health.auth` 中国手机号账号 |
| 在 `i.smali` 里补发 `tnc_sync` 广播（原 ECG 方案 A） | ❌ **永久作废** | setup 流程跑通后 `tnc_complete` 已自动写入，病根不存在了 |
| 刷手表 CSC / 国际固件来支持抗氧化 | ❌ 不需要 | 抗氧化实测已可用 |
| 把手表身份 spoof 成 SM-S921B 之外的值 | ⚠️ 保持现状 | 现值可用，改动会连带影响 capability 协商 |

---

## 附：本文档的证据来源

| 结论 | 证据 |
|---|---|
| setup_init 是总开关 | `out2/helper/f.j()` 读该键；`out2/ld/e0.smali` 的 `:cond_5e` 写入；logcat `isAppInitialized` |
| SA 编译期禁用 | `outA/util/o.smali` 的 `<clinit>`：`const/4 v0,0x0; new-array v0,v0,[String;` |
| Ring 门控 | `outA/fk/h.smali` 的 `n(RingChannel)Z` |
| 保活真判官 | `/data/data/com.miui.powerkeeper/databases/user_configure.db` 的 `userTable.bgControl` |
| 血压已通 | 三星健康 prefs `tracker_bloodpressure_timestamp` |
| AGEs 在传 | `history_database.db` → `sync_history` 的 7 条 `.raw` 记录 |
| 抗氧化可用 | `ANTIOXIDANT_RECENT_SCORE` + `sync_history` + `message_history` |
