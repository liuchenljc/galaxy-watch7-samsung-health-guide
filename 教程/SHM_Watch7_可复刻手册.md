# Galaxy Watch7 (国行) × 非三星 Android：三星健康监测器原生功能解锁 · 从零复刻手册

> 生成：2026-10-01 ｜ 本版：**第三方可复刻**
> 状态：**血压 / 睡眠呼吸暂停 / 心律不齐提醒**已解锁；**心电图（原生）**剩握手死锁（见 §7）
> 适用：**已 root（KernelSU / SukiSU / Magisk）的非三星 Android 手机** + **国行 Galaxy Watch7（SM-L310，One UI 8 Watch）**
> ⚠️ 全程**不刷分区、不动内核**。风险最高的一步也只是重装一个普通 APK。

**本版相比初版的改动**：所有产物与脚本改为随**本仓库**提供（`artifacts/`、`tools/`）；
构建步骤改为**可直接执行的命令**（不再只有叙述）；powerkeeper 改库流程**内联**；
修掉了旧版一处会导致命令失败的回滚拼写错误。

---

## 0. 原理与 5 道锁

三星健康监测器（SHM）在非三星手机上层层设卡，逐个拆：

| # | 锁 | 拆法 | 载体 |
|---|---|---|---|
| 1 | SHM 入口检查 `Build.MANUFACTURER.contains("samsung")`，非三星直接 `finish()` | LSPosed hook `MainActivity.onCreate`，proceed 后无条件改道 `SHealthMonitorMainActivity` | 模块 · `i.smali` |
| 2 | 三星健康 OOBE 的中国版检查（KCB 报 `1048576`） | LSPosed hook `fs90.u() → true` | 模块 · `h.smali` |
| 3 | MIUI 杀后台 / 拦截手表插件后台拉起页面 | powerkeeper 库改 `noRestrict` + MIUI「后台弹出界面」权限放行 | 数据库 + 系统设置 |
| 4 | **地区门**：SIM/网络国家=CN 时 SHM 整体「服务不可用」 | ① 模块 hook `TelephonyManager` 两国籍方法 → `"vn"` ② `resetprop` 设 CSC 属性 | 模块 · `j.smali` + `system.prop` |
| 5 | SHM 条款未同意 → 手表/手机互相踢皮球 | 血压：手机端「校准手表」按钮自带条款流程；心电图：暂未破（见 §7） | 用户操作 |

---

## 1. 复刻前置：需要什么、从哪里获取

### 1.1 硬件 / 软件前提

| 项 | 要求 |
|---|---|
| 手机 | 非三星 Android 12+，**已 root**（KernelSU / SukiSU / Magisk 任一）+ **LSPosed**（或兼容的 libxposed 框架） |
| 手表 | Galaxy Watch7 国行（SM-L310），One UI 8 Watch；**手表端 SHM 换官方版 1.2.7.003**（非 dante63 mod） |
| 电脑 | `adb`；JDK 17；smali/baksmali 2.5.2；uber-apk-signer（构建模块时才需要） |
| 其它 | 一只**袖带血压计**（血压校准用，每 28 天一次，无软件替代） |

### 1.2 工具链来源（构建模块用；本仓库不存二进制）

| 工具 | 获取 |
|---|---|
| JDK 17 | Adoptium Temurin 17（任意发行版即可） |
| smali / baksmali 2.5.2 | Maven `repo1.maven.org`，9 个 jar：`smali`、`baksmali`、`dexlib2`、`util`、`guava-27.1-android`、`jcommander-1.64`、`antlr-runtime-3.5.2`、`stringtemplate-3.2.1`、`antlr-3.5.2`、`failureaccess-1.0.1`（见 §5 一键下载脚本） |
| uber-apk-signer 1.3.0 | GitHub `patrickfav/uber-apk-signer` Releases |

> 若你**不需要重建模块**（直接用本仓库的 v7 APK），1.2 整节可跳过。

### 1.3 本仓库自带的产物清单

| 路径 | 是什么 | 怎么用 |
|---|---|---|
| `artifacts/module/spoof_module_v7_signed.apk` | **最终可用模块**（已含上表 5 个 hook 里的 1/2/4） | 直接 `adb install`（见 §4 第 4 步） |
| `artifacts/module/spoof_module_original.apk` | 原始模块（未打补丁） | ① 作为重建时的 APK 外壳 ② 回滚用 |
| `artifacts/module/smali_v7/` | 补丁后**完整 smali 源码**（11 个 .smali，从 v7 APK 反汇编得来，真源） | 重建用（§5 方式 B） |
| `artifacts/shm_watch7_fix/` | KernelSU 持久化模块源（`module.prop`/`service.sh`/`system.prop` + README） | §4 第 9 步（**注意：`user_configure_fixed.db` 需你自建，见该目录 README**） |
| `tools/build_module.sh` | 一键重建脚本（smali 汇编→重打包→签名） | §5 |
| `tools/axml_scan.py`、`tools/arsc_strings.py` | 二进制 AndroidManifest / resources.arsc 解析器（取证用，可选） | 分析 APK 时 |

### 1.4 关于路径的约定（重要）

- 本手册中凡以 `artifacts/…`、`tools/…`、`docs/…` 开头的，都是**本仓库根目录下的相对路径**。
- 旧版手册里出现的 `diag/…`、`ZCode workspace/…`、`WorkBuddy/…` 是**作者本机私有路径**，你机器上不存在，本版已全部替换为仓库路径或"自建"。
- 命令里的 `$A` 统一代表 **`adb -s <你的序列号>`**（多设备时必须带 `-s`）：
  ```bash
  export MSYS_NO_PATHCONV=1        # Git Bash on Windows 必须，否则 /data/... 会被转成 Windows 路径
  A="adb -s <SERIAL>"              # ← 换成你的序列号（adb devices 查看）
  ```
- root 执行多命令统一写法：`$A shell "su -c 'cmd1; cmd2'"`。

---

## 2. 五项改动（每项：做什么 / 命令 / 验证 / 回滚）

### 2.1 模块补丁（入口改道 + KCB + 地区伪装）★核心

- 模块：`com.arnold.spoofsamsung.Hook`（入口类 `SpoofSamsungModule`，libxposed 新 API）
- 三个补丁 Hooker：
  - `h.smali`（`ShealthChinaBuildHooker`）：hook `fs90.u()` → `true`（跳过 KCB）
  - `i.smali`（`ShmMainActivityHooker`）：hook `MainActivity.onCreate` → 非三星时改道 `SHealthMonitorMainActivity`
  - `j.smali`（`ShmCountryHooker`）：hook `TelephonyManager.getNetworkCountryIso()` 与 `getSimCountryIso()` → 返回 `"vn"`
- **推荐做法**：直接用 `artifacts/module/spoof_module_v7_signed.apk`（见 §4）。
- 想自己重建 → 见 **§5**（`tools/build_module.sh` 一键完成）。
- 验证（logcat 应出现）：
  ```
  HOOK REGISTERED: shealthmonitor.mainactivity
  HOOK REGISTERED: shealth.china.build (fs90.u -> true)
  HOOK REGISTERED: shealthmonitor.country (network/sim iso -> vn)
  OnboardingUtil current Network : VN
  ```
- 回滚：`$A uninstall com.arnold.spoofsamsung.Hook`，再装 `artifacts/module/spoof_module_original.apk`，
  重启后在 LSPosed 里重新勾选启用。

### 2.2 CSC 属性（与 §2.1 的地区 hook 缺一不可）

```bash
$A shell "su -c 'resetprop ro.csc.sales_code XXV; \
                resetprop ro.csc.countryiso_code VN; \
                resetprop ro.csc.iso_code VN'"
```

- 只设 hook 不设属性：标签栏解锁（3 个标签）但**血压页仍「服务不可用」**。
- 只设属性不设 hook：校准页出现约 1 分钟后被 SIM 国家(CN) 翻回去。
- **两个都设 → 校准页稳定。**
- 持久化：已封装进 `artifacts/shm_watch7_fix/system.prop`（§4 第 9 步）。

### 2.3 powerkeeper 省电库（防手表断连 / 后台拦截）

7 个三星包的 `bgControl` 全部改 `noRestrict`。**完整可执行流程见 §6**（本版已内联，不再外链）。
- **云端会回滚**（实测 ~30 分钟内）：长效对抗见 `artifacts/shm_watch7_fix/`（`service.sh` 每 15 分钟恢复）。
- 回滚：恢复你改库前的备份（§6 第 ① 步会生成）。

### 2.4 MIUI「后台弹出界面」权限

- 设置 / 手机管家 → 给 **「Galaxy Watch7 Manager（watch7plugin）」** 和 **「三星配件服务（com.samsung.accessory）」** 开启「后台弹出界面」。
- 这项**不走 powerkeeper**，UI 放行一次即持久（存 LBE `permission_db`）。
- ⚠️ 与 §2.3 是**两级独立检查，都要放行**。

### 2.5 KernelSU 持久化模块 `shm_watch7_fix`

- 源码：本仓库 `artifacts/shm_watch7_fix/`
- `system.prop`：§2.2 的三条 CSC 属性（开机自动应用）
- `service.sh`：开机 180s 后 + 每 900s，把模块内的 `user_configure_fixed.db` 覆盖到 powerkeeper 库
- ⚠️ **`user_configure_fixed.db` 需你自建**（每台机不同，见该目录 `README.md`）
- ⚠️ 副作用：快照是整库，期间其它 App 的省电设置改动会被 15 分钟循环覆盖
- 安装：见 §4 第 9 步｜卸载：`$A shell "su -c 'rm -rf /data/adb/modules/shm_watch7_fix'"` + 重启

### 2.6 清理项

- 卸载手机上的 dante63 手表包残留 `com.samsung.android.shealthmonitors`（92MB）：
  `$A shell "pm uninstall -k --user 0 com.samsung.android.shealthmonitors"`
- 三星健康「数据权限」弹窗：总开关（所有权限）全部允许 —— 这是 SHM↔三星健康的数据通道。

---

## 3. 复刻步骤（新机从零）

1. 手机装 SHM 官方版（Galaxy 商店 / APKMirror，1.5.x）、Galaxy Wearable + watch7plugin，配对手表。
2. 三星健康「数据权限」全放行（弹窗或设置里）。
3. MIUI：后台弹出界面放行 watch7plugin + accessory（§2.4）；powerkeeper 改库（§6）。
4. 装 §2.1 的伪装模块：`artifacts/module/spoof_module_v7_signed.apk`（§4 第 4 步）。
5. 设 §2.2 CSC 属性。
6. 打开 SHM → **血压页应显示「校准手表」按钮**（不再「服务不可用」）。
7. 点校准 → 同意条款 → **用袖带血压计校准**（每 28 天一次）。
8. 手表测量 → 数据自动同步到 SHM 历史记录。
9. 装 §2.5 持久化模块 → 重启 → 全部固化。

---

## 4. 逐步可执行清单

> 前置：`export MSYS_NO_PATHCONV=1`；`A="adb -s <序列号>"`。

**① 装 SHM 与穿戴组件**：从应用商店 / APKMirror 装 `com.samsung.android.shealthmonitor`（1.5.x）、
`com.samsung.android.app.watchmanager`（Galaxy Wearable）、`com.samsung.wearable.watch7plugin`。

**② 数据权限**：打开一次 SHM，弹「三星健康数据权限」时点「所有权限 → 完成」。
（adb 无法代点，见 §7 备注。）

**③ MIUI 放行**：
```bash
# 后台弹出界面：设置 UI 里手动开（watch7plugin + com.samsung.accessory）
# powerkeeper 改库：见 §6
```

**④ 装模块**（重签名模块与系统里的旧版签名冲突，必须先卸）：
```bash
$A uninstall com.arnold.spoofsamsung.Hook 2>/dev/null
$A install -r artifacts/module/spoof_module_v7_signed.apk
# 重启后：LSPosed → 模块 → 启用 com.arnold.spoofsamsung.Hook，作用域勾选：
#   com.samsung.wearable.watch7plugin / com.sec.android.app.shealth /
#   com.samsung.android.shealthmonitor / com.samsung.wearable.watchuniteplugin
```

**⑤ 设 CSC 属性**：`$A shell "su -c 'resetprop ro.csc.sales_code XXV; resetprop ro.csc.countryiso_code VN; resetprop ro.csc.iso_code VN'"`

**⑥ 验证解锁**：
```bash
$A logcat -d | grep -aE "HOOK REGISTERED|current Network"
# 期望：三个 HOOK REGISTERED + current Network : VN
```

**⑦ 校准血压**：SHM → 血压 → 「校准手表」→ 同意条款 → 按提示用袖带校准。

**⑧ 手表测量**：手表打开 SHM → 选血压/心电图 → 按提示测量。

**⑨ 装持久化模块**：
```bash
# 先按 artifacts/shm_watch7_fix/README.md 生成 user_configure_fixed.db 放进该目录
$A push artifacts/shm_watch7_fix /data/adb/modules/shm_watch7_fix
$A shell "su -c 'chmod 755 /data/adb/modules/shm_watch7_fix/service.sh'"
$A reboot
```

---

## 5. 模块重建（可选；两种方式）

### 方式 A：直接用仓库里的成品（最快）

```bash
adb install -r artifacts/module/spoof_module_v7_signed.apk
```
（完整性校验：`md5sum artifacts/module/spoof_module_v7_signed.apk`，应为
`653556e3ffe91c255a1e6297ba2e743d`。）

### 方式 B：从 smali 源码重建

**B-0 准备工具链**（把 9 个 jar 下到同一目录，例如 `apk/smali/`）：
```bash
mkdir -p apk/smali && cd apk/smali
B=https://repo1.maven.org/maven2
curl -LO $B/com/android/tools/smali/smali/2.5.2/smali-2.5.2.jar
curl -LO $B/com/android/tools/smali/dexlib2/2.5.2/dexlib2-2.5.2.jar
curl -LO $B/com/android/tools/smali/util/2.5.2/util-2.5.2.jar
curl -LO $B/com/google/guava/guava/27.1-android/guava-27.1-android.jar
curl -LO $B/com/beust/jcommander/1.64/jcommander-1.64.jar
curl -LO $B/org/antlr/antlr-runtime/3.5.2/antlr-runtime-3.5.2.jar
curl -LO $B/org/antlr/stringtemplate/3.2.1/stringtemplate-3.2.1.jar
curl -LO $B/org/antlr/antlr/3.5.2/antlr-3.5.2.jar
curl -LO $B/com/google/guava/failureaccess/1.0.1/failureaccess-1.0.1.jar
# 签名器（GitHub Releases 下载 uber-apk-signer-1.3.0.jar）放到 apk/
cd ../..
```

**B-1 一键重建**（会读 `artifacts/module/spoof_module_original.apk` 作外壳 + `artifacts/module/smali_v7/` 作源码）：
```bash
JAVA="<你的 JDK17>/bin/java" \
SMALI_DIR="$PWD/apk/smali" \
SIGNER="$PWD/apk/uber-apk-signer.jar" \
bash tools/build_module.sh
# 产物：build/signed/spoof_v7_unsigned-aligned-debugSigned.apk
```

**B-2 等价的手工命令**（若你想逐步做）：
```bash
# 1) 汇编 smali -> classes.dex
java -Xmx2g -cp "apk/smali/*" org.jf.smali.Main a artifacts/module/smali_v7 -o build/classes_new.dex
# 2) 重打包：用 classes_new.dex 替换原 APK 的 classes.dex，重写 scope.list，剔除 META-INF 旧签名
#    （逻辑与 tools/build_module.sh 里的 Python 段一致；作用域 4 个包）
# 3) 签名
java -jar apk/uber-apk-signer.jar --apks build/spoof_v7_unsigned.apk \
     --out build/signed --allowResign --overwrite
```
- ⚠️ uber-apk-signer 的 `--out` 接**目录**，且与 `--overwrite` 搭配使用。
- ⚠️ Windows 下 classpath 用 `;` 分隔，非 Windows 用 `:`（`build_module.sh` 已自动识别）。
- 签名用随机 debug keystore → **每次重建都要先 `uninstall` 再 `install`**。

**想改 hook 怎么办**：改 `artifacts/module/smali_v7/` 里对应文件后重跑 B-1。三个 Hooker 的语义见 §2.1。
`SpoofSamsungModule.smali` 的 `onPackageLoaded` 是分发入口，决定哪个包加载哪些 hook。

---

## 6. powerkeeper 改库（完整流程，已内联）

手机**无 `sqlite3`**，必须 pull 到 PC 改再 push。

```bash
export MSYS_NO_PATHCONV=1
A="adb -s <序列号>"

# ① 备份（先做，回滚靠它）
$A shell "su -c 'cp -a /data/data/com.miui.powerkeeper/databases/user_configure.db \
  /sdcard/uc_backup_$(date +%Y%m%d).db'"

# ② 停 powerkeeper 后拉库（避免 -wal 未落盘）
$A shell "su -c 'am force-stop com.miui.powerkeeper; sleep 1; \
  cp /data/data/com.miui.powerkeeper/databases/user_configure.db /sdcard/uc.db; \
  chmod 666 /sdcard/uc.db'"
$A pull /sdcard/uc.db uc.db
```

③ PC 端（Python）把目标包改成 `noRestrict`：
```python
import sqlite3, time
c = sqlite3.connect('uc.db')
pkgs = ['com.samsung.wearable.watch7plugin', 'com.samsung.accessory',
        'com.samsung.android.app.watchmanager', 'com.samsung.android.shealthmonitor',
        'com.samsung.android.shealthmonitors', 'com.sec.android.app.shealth',
        'com.arnold.spoofsamsung.Hook']
for p in pkgs:
    c.execute("update userTable set bgControl='noRestrict', lastConfigured=?, "
              "bgLocation=NULL, bgDelayMin=NULL where pkgName=?", (int(time.time()*1000), p))
c.commit(); c.close()
```

④ 写回（**必须 chown/chmod，否则 powerkeeper 读写失败**）：
```bash
$A push uc.db /sdcard/uc_new.db
$A shell "su -c 'am force-stop com.miui.powerkeeper; sleep 1; \
  cp /sdcard/uc_new.db /data/data/com.miui.powerkeeper/databases/user_configure.db; \
  chown system:system /data/data/com.miui.powerkeeper/databases/user_configure.db; \
  chmod 660 /data/data/com.miui.powerkeeper/databases/user_configure.db; \
  rm -f /data/data/com.miui.powerkeeper/databases/user_configure.db-journal'"
```

⑤ 复核（防内存旧值回滚）：
```bash
$A shell "su -c 'cp /data/data/com.miui.powerkeeper/databases/user_configure.db /sdcard/v.db; \
  chmod 666 /sdcard/v.db'"
$A pull /sdcard/v.db v.db
python -c "import sqlite3;[print(r) for r in sqlite3.connect('v.db').execute(\"SELECT pkgName,bgControl FROM userTable WHERE pkgName LIKE '%samsung%' OR pkgName='com.sec.android.app.shealth'\")]"
```

⑥ 生成本仓库持久化模块要用的快照（`artifacts/shm_watch7_fix/README.md` 也写了）：
```bash
cp uc.db artifacts/shm_watch7_fix/user_configure_fixed.db
```

---

## 7. 已知未解

- **心电图原生握手死锁**：ECG 条款无手机端入口（血压有校准按钮），手表等手机、手机等手表。
  已试并否决：条件改道、独立条款页（无同意键）、以 SHM uid 直接拉起条款 Activity（包名身份校验拒绝）、
  伪造 deep link（参数校验）。**候选突破口**：`ActionRequestActivity` 的路径协议逆向，或 hook 条款完成状态。
- **血压校准链路的手表侧应答**：日志铁证 `BPInformation onError TIMEOUT {"action":"bp_module_disable_state"}`
  ——手表对功能消息超时不答（疑手表 CHC 固件地区门）。若确认在手表侧，只能刷手表 CSC（高风险）或放弃。
- **powerkeeper 云端回滚**是与 MIUI 云的长期对抗，15 分钟自愈循环是妥协方案。
- **血压校准依赖袖带硬件**（每 28 天），无软件替代。
- **抗氧化指数**：Watch7 硬件产品线不支持（仅 Watch Ultra / 8+），与地区/固件无关，勿再尝试。
  （注意：这与 **AGEs 指数**是**两个功能**，后者 Watch7 官方支持——见 `docs/antioxidant-ages-gating.md`。）
- **备注**：MIUI 下 root 合成触摸（`input tap`）无效，需点 UI 的步骤只能**人工手点**。

---

## 8. 文件与备份索引

| 文件 | 位置 |
|---|---|
| 最终模块（v7，已签名） | `artifacts/module/spoof_module_v7_signed.apk`（md5 `653556e3…`） |
| 原始模块（外壳 / 回滚） | `artifacts/module/spoof_module_original.apk`（md5 `c3b92da3…`） |
| 模块 smali 源码（v7 真源） | `artifacts/module/smali_v7/` |
| 持久化模块源 | `artifacts/shm_watch7_fix/`（`user_configure_fixed.db` 需自建） |
| 构建脚本 | `tools/build_module.sh` |
| 取证脚本 | `tools/axml_scan.py`、`tools/arsc_strings.py` |
| 本机备份（作者侧） | 设备 `/sdcard/uc_backup_*.db`（powerkeeper 库快照） |

---

## 9. 法律与安全

- 所有操作仅改用户空间（APK / 系统属性 / 数据库），**不碰分区内核**；但仍可能违反三星服务条款。
- 血压 / 心电数据未经医疗认证，**不能作为诊断依据**。
- 涉及地区伪装与账号，请仅用于**你自己的设备**排障研究，勿用于隐瞒测量局限或他人设备。
