# Galaxy Watch7 在非三星手机上使用三星健康功能

> 完整可复刻教程。
>
> 本包**不含任何三星官方 APK**（需自行从官方渠道获取，见 §3），
> 也不含 LSPosed 伪装模块（第三方作品，许可状态见 [归属声明](ATTRIBUTION_归属声明.md)）。
>
> **包含**：本项目原创的 KSU 持久化模块（MIT，可直接装）+ 完整教程 + 24 个已踩过的坑。

---

## 目录

- [1. 这是什么](#1-这是什么)
- [2. 前置条件](#2-前置条件)
- [3. 你需要自己获取的东西](#3-你需要自己获取的东西)
- [4. 原理：两道锁 + 一个杀手](#4-原理两道锁--一个杀手)
- [5. 安装步骤](#5-安装步骤)
- [6. 验证](#6-验证)
- [7. 已知不可用的功能](#7-已知不可用的功能)
- [8. 常见问题](#8-常见问题)
- [9. 安全与免责](#9-安全与免责)
- [10. 归属与许可](#10-归属与许可)

---

## 1. 这是什么

Galaxy Watch7 的完整健康功能（血压、心电图、AGEs、抗氧化指数、睡眠呼吸暂停）需要配套的三星手机
App 才能使用。三星只在自家手机预装这些 App。

本项目让这些 App 在**非三星 Android 手机**上工作，用到：

| 层 | 手段 | 作用 |
|---|---|---|
| Java 层 | **LSPosed 模块**（需自建，见 §4 与归属声明） | 绕过厂商白名单 + 地区门 |
| 系统层 | **KernelSU 模块**（本包提供 zip + 源码） | 开机注入地区属性 + 每 5 分钟自愈后台限制 + 守护传输进程 |

**两个缺一不可。** 少 LSPosed 模块 = 闪退打不开；少 KSU 模块 = 能开但时好时坏。

### 已验证可用的功能

| 功能 | 状态 |
|---|---|
| 常规健康（步数/睡眠/心率/体成分） | ✅ |
| 血压（手机指挥手表 + 数据回写） | ✅ |
| 心电图 ECG | ✅ |
| AGEs（糖基化终末产物） | ✅ |
| 抗氧化指数 | ✅（需装第三方启动器拉起原生界面） |
| 睡眠呼吸暂停 SA | ⚠️ 手机侧解锁，**手表端不可用**（见 §7） |

---

## 2. 前置条件

### 硬件

| 项 | 要求 |
|---|---|
| 手机 | **已解锁 BL** 的 Android 11+ 设备，arm64-v8a |
| 手表 | Galaxy Watch7（SM-L310）或同类三星 Watch |

### 手机端

| 依赖 | 版本 | 用途 |
|---|---|---|
| KernelSU | ≥ 最新版 | root。**或**用 LKM 模式 |
| Zygisk Next | 1.5.0 (843) | 注入层 |
| LSPosed / **Vector** | **2.x**（如 v2.2） | 加载模块。⚠️ 见下方警告 |
| adb + fastboot | 任意近期版本 | 调试与刷机 |

> ### ⚠️ LSPosed 版本是硬门槛
> 伪装模块用的是 **libxposed 新 API**（`minApiVersion=102`）。
> **LSPosed 1.9.x 装了不报错，但模块完全不会加载**（日志零条 hook 记录），极易误判成模块坏了。
> 必须用 **2.x**。LSPosed 现名 **Vector**（JingMatrix 维护），模块 id 从 `zygisk_lsposed` 变成 `zygisk_vector`。

### 电脑端

- Python 3.7+（仅用于辅助脚本）
- smali/baksmali 2.5.2（**仅重编模块时需要**，9 个 jar 必须同版本）
- uber-apk-signer 1.3.0（仅重签时需要）
- JDK 17（仅重编时需要）

> 工具链体积大且与平台无关，**不随本包分发**，需自行按版本表准备。

---

## 3. 你需要自己获取的东西

> **本包不提供以下文件。** 它们是三星 / 各项目的官方或公开发行版本，
> 自行获取也符合各自的使用条款。

### 3.1 四个三星 App（必须，从 Galaxy Store 装）

| 包名 | 应用 | 说明 |
|---|---|---|
| `com.sec.android.app.shealth` | 三星健康 | 主应用 |
| `com.samsung.android.shealthmonitor` | 三星健康监测器 | **血压/心电图/SA 的核心** |
| `com.samsung.android.app.watchmanager` | Galaxy Wearable | 手表配对与插件管理 |
| `com.samsung.wearable.watch7plugin` | Watch7 插件 | 手表能力信息 |

**获取途径**：手机端 Galaxy Store（`galaxystore.samsung.com`），或从任何能装三星健康的三星设备 `pm path` 导出。

> ### ⚠️ 必须是官方原版
> 这套方案是「**官方包 + LSPosed 运行时打补丁**」。换成第三方改版（签名不同），
> 整个方案失效 —— 因为 signature-level 权限和 sharedUserId 都对不上。
> 验证方法见 §6.1。

### 3.2 第三方应用（可选）

| 用途 | 包名 | 说明 |
|---|---|---|
| 抗氧化指数启动器 | `com.skya.antioxidantsindex` | 纯图标壳，只把原生测量界面拉起来 |
| 备用心电图 | `com.geminiman.wellness.companion` | 双端 |

### 3.3 本包提供的东西

```
模块/
  shm_watch7_fix_v5.zip         KSU 持久化模块（46 KB）★本项目原创，MIT
模块源码/
  shm_watch7_fix/               KSU 模块完整源码（service.sh / system.prop / module.prop）
工具/
  build_module.sh               smali 重建脚本
  sanitize.py                   文档脱敏
教程/                           5 份深度文档
知识包/                         24 个已踩过的坑（8 类索引）
```

> ### ⚠️ 关于 LSPosed 伪装模块
>
> 伪装模块（LSPosed）**不在本包内**。原因见
> [`ATTRIBUTION_归属声明.md`](ATTRIBUTION_归属声明.md)：
>
> - 该模块（包名 `com.arnold.spoofsamsung.Hook`）是**第三方作品**，本项目只做了修改
> - 原 APK **未含任何作者或许可声明** → 许可状态为「保留所有权利」
> - 因此本包**不分发其预编译 APK 与反编译源码**
>
> **想自己做的话**，本教程 §4 已完整说明 4 个 hook 的目标与方法：
>
> | # | 目标 | 改法 |
> |---|---|---|
> | 1 | `fs90.u()` | 返回 `true`，绕过中国版构建检查 |
> | 2 | `SHM MainActivity.onCreate` | 改道入口，绕过厂商白名单 |
> | 3 | `TelephonyManager.getSimCountryIso()` | 返回 `"vn"`，地区伪装 |
> | 4 | `SHM util/o.b0()` | 返回 `true`，解锁 SA 通道 |
>
> 用 libxposed API（`minApiVersion=102`）写这样一个模块并不复杂，
> 核心就是这 4 个 `HookBuilder.intercept()`。

---

## 4. 原理：两道锁 + 一个杀手

### 锁 1：厂商白名单（代码层）

`com.samsung.android.shealthmonitor` 的 `MainActivity.onCreate` 检查
`Build.MANUFACTURER.contains("samsung")`，非三星 → `finish()`。
表现是「点开就闪退」。

### 锁 2：地区门（代码层）

SHM 校验 SIM 国家码后才放行血压 / 心电图 / SA / 抗氧化。中国区部分功能被关。

### 杀手：MIUI / ColorOS 后台限制（系统层）

`/data/data/com.miui.powerkeeper/databases/user_configure.db` 的 `userTable.bgControl` 字段。
三星包默认 `miuiAuto`（限制后台），**云端会周期性改回**。
表现是「用一会儿就连不上了」。

### 解法组合

```
LSPosed 模块（4 个 hook）
  ├─ fs90.u()                    → true     绕过中国版构建检查（KCB）
  ├─ SHM MainActivity.onCreate   → 改道入口  绕过厂商白名单
  ├─ getSimCountryIso()          → "vn"     地区伪装
  └─ SHM util/o.b0()             → true     解锁 SA 通道

KSU 模块
  ├─ system.prop   开机注入 ro.csc.countryiso_code=VN
  ├─ service.sh    每 300 秒：① 恢复 powerkeeper 快照 ② 守护 SAP 进程
  └─ 快照 db       8 个包的 noRestrict 正确态
```

---

## 5. 安装步骤

### 步骤 0 · 准备

```bash
# 装 Zygisk 与 LSPosed（每次只装一个，重启验证再装下一个）
# SukiSU / KernelSU → 设置里打开 Zygisk → 重启
# SukiSU → 模块 → 从本地安装：
#   Zygisk-Next-*.zip           → 重启
#   Vector-*.zip  (或 LSPosed 2.x) → 重启
```

验证：
```bash
adb shell su -c id                # uid=0(root)
adb shell "su -c 'ls /data/adb/modules/'"   # 应含 zygisk_next / zygisk_vector
```

### 步骤 1 · 装四个三星 App

从 Galaxy Store 装，或 `adb install -r <apk>`。

### 步骤 2 · 装伪装模块

> 本包不分发该模块（见 [归属声明](ATTRIBUTION_归属声明.md) §2）。
> 二选一：自己按 §4 描述实现，或从你已确认授权的渠道获取。

实现要点（libxposed API，`minApiVersion=102`）：

```
META-INF/xposed/module.prop
  minApiVersion=102  targetApiVersion=102  staticScope=true

META-INF/xposed/scope.list
  com.samsung.wearable.watchuniteplugin
  com.samsung.wearable.watch7plugin
  com.sec.android.app.shealth
  com.samsung.android.shealthmonitor

assets/xposed_init
  你的入口类全名
```

```kotlin
class Hook : XposedModule() {
    override fun onPackageLoaded(p: PackageLoadedParam) {
        when (p.packageName) {
            "com.sec.android.app.shealth"      -> hookKcb(p.classLoader)
            "com.samsung.android.shealthmonitor" -> hookShm(p.classLoader)
            // watch7plugin / watchuniteplugin 同理
        }
    }
}
```

4 个 hook 的目标与方法见 §4 表格。装完只需重启目标应用，不必重启手机：

```bash
adb shell su -c "am force-stop com.samsung.android.shealthmonitor"
adb shell su -c "am force-stop com.sec.android.app.shealth"
```

### 步骤 3 · 装 KSU 持久化模块

```bash
K=/data/adb/modules/shm_watch7_fix
adb shell su -c "mkdir -p $K"
adb push 模块/shm_watch7_fix_v5.zip /data/local/tmp/
adb shell su -c "ksud module install /data/local/tmp/shm_watch7_fix_v5.zip"
adb reboot                    # 必须重启
```

> 也可以在 SukiSU / KernelSU → 模块 → 从本地安装 里选那个 zip。

### 步骤 4 · ★ 填个人资料（最容易被漏）

打开手机上的「三星健康监测器」：

1. 同意条款
2. 出现「**编辑个人资料**」→ **改一下出生日期**（让「保存」变亮）→ 填 **2004 年或更早** → **点保存**

> ### ⚠️ 这一步是血压和心电图的总开关
> 它写入 pref `shealth_monitor_base_app_setup_init`，**只由这个页面的保存按钮写入**。
> 不保存 → 手机发不出测量指令 → 手表测不了。
> （这也是为什么某些 LSPosed 入口改道方案会导致血压/心电图失效 —— 绕过了 Setup 链。）

### 步骤 5 · 开「后台弹出界面」权限

**设置 → 应用管理 → Galaxy Wearable → 权限 → 「后台弹出界面」→ 允许**
（`com.samsung.accessory` 如有此项也开一遍）

> 这一项**没有 adb 命令能开**，只能手点。
> 不做的症状：手表提示"到手机上操作"，手机毫无反应。

### 步骤 6 · 蓝牙重连

如果手表之前绑过别的手机：
**设置 → 蓝牙 → 找到 Watch7 → 取消配对**，然后在 Galaxy Wearable 里重新连（**不要重置手表**）。

---

## 6. 验证

### 6.1 确认是官方原版包

```bash
# 证书 Subject 必须含 O=Samsung Corporation, L=Suwon City
unzip -p <shealth.apk> META-INF/*.RSA | keytool -printcert 2>/dev/null | grep -E "O=|L="
```

### 6.2 关键属性

```bash
adb shell getprop ro.csc.countryiso_code          # 期望 VN
adb shell su -c "ls /data/adb/modules/"           # 含 shm_watch7_fix
adb shell su -c "tail -5 /data/adb/modules/shm_watch7_fix/self_heal.log"
```

`self_heal.log` 里看到 `OK 已恢复快照` 和 `OK SAP 已拉起` 说明守护在跑。

### 6.3 链路判据

```bash
# powerkeeper 放行数（期望 ≥8）
adb shell su -c "grep -a -o noRestrict /data/data/com.miui.powerkeeper/databases/user_configure.db | wc -l"

# SHM 初始化总开关
adb shell su -c "grep -c setup_init /data/data/com.samsung.android.shealthmonitor/shared_prefs/permanent_shared_preferences_main.xml"

# 血压是否回写三星健康
adb shell su -c "grep -ahoE 'tracker_bloodpressure_timestamp[^0-9]*[0-9]+ /data/data/com.sec.android.app.shealth/shared_prefs/*.xml | sort -u"
```

> ### ⚠️ 写 adb 判据的三个经典假阴性
> ① `grep -c` **只输出数字**（输出 `"1"`），不能用 `"setup_init" in 输出` 判断存在性 → 解析整数
> ② 判据的 grep 模式串本身会被 logcat 记成 adbd 命令行日志 → 永远命中 → 用字符类打断，如 `not supported i[n]`
> ③ shell 包一层 `su -c '...'` 后，正则里的单引号会破坏嵌套 → 用 `i[n]` 之类打断

### 6.4 最直接的验证

**手表 → 三星健康监测器 → 心电图 → 按住按钮 30 秒**，手机上看记录。

---

## 7. 已知不可用的功能

### 睡眠呼吸暂停（SA）— 手表端不可用

**现象**：手机侧已解锁（`feature version` 1 → 2，SLEEP 节点出现，logcat 不再报
`skip onNodeChanged ... not supported`），但**手表端 SHM 菜单里没有该入口**。

**根因**：手表端 SHM 构建时该功能被**编译期禁用**，菜单项根本不存在。
手机侧的 hook 只能解锁手机侧通道，无法凭空造出手表端菜单。

**为什么攻不下**：Watch7 是 user build，无 root，上不了 LSPosed；
而手表端 SHM 无法重新编译。

**结论**：手机侧保持解锁状态（万一未来固件放开就能直接用），但**不要期待手表端可用**。

---

## 8. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| SHM 点开闪退 | 伪装模块没加载 | ① 确认 LSPosed 是 **2.x**（1.9.x 静默失败）② 确认作用域含 4 个包 ③ force-stop 目标应用 |
| 血压/心电图页面显示"服务不可用" | `setup_init` 没写入 | 重做 §5 步骤 4 |
| 用一会儿就连不上 | powerkeeper 回滚 | 确认 KSU 模块在位，看 `self_heal.log` |
| 手表唤不起手机 | 后台弹出界面权限没开 | 重做 §5 步骤 5 |
| 提示"需要重置手表" | 蓝牙配对记录错乱 | **先别重置**。见知识包 `06_配对与数据链路.md` F1/F2 |
| 心电图能测但手机没记录 | 数据权限没给 | 三星健康 → 隐私 → 数据权限 → 允许 |
| 改完没效果 | 判断错了 | ① LSPosed 日志里有没有 hook 记录 ② 判据是不是假阴性（见 6.3） |

完整排查见 `知识包/问题排查知识包_20261003/README_总览索引与快速排查.md`（24 个已踩过的坑）。

---

## 9. 安全与免责

### 关于本包

- 本包**不含任何三星官方 APK**，需自行从官方渠道获取
- 包含的模块是自制第三方作品，与三星无关
- 所有安装操作只改**用户空间**（APK / 系统属性 / 数据库），不碰分区内核（除非你自己选择刷 init_boot 拿 root）

### 风险提示

1. **违反服务条款**：绕过厂商的区域限制可能违反三星服务条款，导致账号被限制。**请只用于你自己的设备。**
2. **健康数据不可用于诊断**：血压 / 心电数据未经医疗认证。
3. **刷机有变砖风险**：刷 `init_boot` 前务必备份原版镜像。**刷错分区（boot 而非 init_boot）会变砖。**
4. **模块来源请自行判断**：本包模块用 debug keystore 签名（仅用于 LSPosed 加载，无系统权限需求），
   与任何官方签名都不同，无法用于覆盖安装官方应用。

### 隐私

本仓库文档已做脱敏处理：不含真实姓名、MAC 地址、设备序列号、Windows 用户名、API 密钥。
设备相关值一律用占位符 `<SERIAL>` / `<DEVICE_ID>` / `<WATCH_MAC>` / `<PHONE_MAC>` / `%USERPROFILE%` / `<LAN_IP>`。

---

## 10. 目录结构

```
.
├── ATTRIBUTION_归属声明.md    ★ 先读这个（版权与许可状态）
├── 模块/                      预编译模块（直接可用）
│   └── shm_watch7_fix_v5.zip  KSU 模块（★本项目原创，MIT）
├── 模块源码/                  完整源码，可自行重编
│   └── shm_watch7_fix/        KSU 模块源码
│                              （LSPosed 模块源码不在本包，见归属声明 §2）
├── 工具/
│   ├── build_module.sh        从 smali 重建 + 签名
│   └── sanitize.py            文档脱敏
├── 教程/
│   ├── MASTER_全流程.md       ★ 总纲，先读这个
│   ├── SHM_Watch7_可复刻手册.md
│   ├── kcb-bypass-hook.md
│   ├── miui-powerkeeper-balkill.md
│   └── 睡眠呼吸暂停专项_20261002.md
└── 知识包/问题排查知识包_20261003/
    ├── README_总览索引与快速排查.md    ★ 出问题时先开这个
    ├── 01_环境与工具链.md              A1–A6
    ├── 02_root与模块.md                B1–B5
    ├── 03_MIUI拦截三件套.md            C1–C3
    ├── 04_三星应用层.md                D1–D7
    ├── 05_手表侧.md                    E1–E6
    ├── 06_配对与数据链路.md            F1–F3
    ├── 07_诊断方法论与陷阱.md          G1–G3
    ├── 08_GitHub上传通道.md            H1–H2
    └── 09_附录_环境快照.md
```

---

## 附：重建模块

```bash
# 需要：JDK 17、smali 2.5.2（9 个 jar）、uber-apk-signer 1.3.0
bash 工具/build_module.sh
```

⚠️ uber-apk-signer **不能同时给 `--out` 和 `--overwrite`**（1.3.0 会报参数冲突）。

---

*本教程仅用于技术学习与个人设备排障研究。请勿用于商业或侵害他人权益的用途。*

---

## 10. 归属与许可

| 组成 | 作者 | 许可 | 本包是否提供 |
|---|---|---|---|
| `shm_watch7_fix` KSU 模块 | `liuchenljc` | **MIT** | ✅ 预编译 + 源码 |
| 教程 / 知识包 / 脚本 | `liuchenljc` | 见仓库 | ✅ |
| `com.arnold.spoofsamsung.Hook` | **第三方，原作者未知** | **保留所有权利** | ❌ 不分发 |
| 四个三星应用 | Samsung | 三星版权 | ❌ 不分发 |
| smali / uber-apk-signer / JDK / adb 等工具 | 各项目 | Apache-2.0 / MIT / GPL | ❌ 读者自备 |

**如果你就是 `com.arnold.spoofsamsung.Hook` 的作者**，请联系仓库 owner，
本项目会补上你的署名与许可声明，并把 4 项修改整理成规范 patch 供你合并。

本项目由 `liuchenljc` 与 AI 助手 LC 协作完成。
