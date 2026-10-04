# 03 · MIUI 拦截三件套

**严重程度图例**：P0=核心功能不可用 ｜ P1=绕过成本高 ｜ P2=一次性配置

**引言（这三层拦截的关系）**：MIUI/HyperOS 对「手表↔手机」链路的拦截分三层，各查各的、互相独立——① **省电库（powerkeeper）管后台存活**：三星应用的进程能不能在后台活着、数据通道能不能维持（→ C1）；② **「后台弹出界面」权限管页面拉起**：活着的后台进程能不能把界面弹到前台，承接手表发起的跳转（→ C2）；③ **合成触摸限制管自动化调试**：adb/自动化能不能代替真人手指点屏幕（→ C3）。三层是独立检查，只修一层不够——实测修完 C1 省电库后，C2 依然静默拦截；C3 只影响自动化、不影响真人使用。现象分诊一句话：**手机打开了但没数据 → 查 C1；手机毫无反应、页面根本没拉起 → 查 C2；自动化点不动但真人能点 → 查 C3。**

## 环境速览（本机事实，下文命令直接引用）

```text
adb        %USERPROFILE%\Desktop\platform-tools\adb.exe
           Git Bash 里写 %USERPROFILE%/Desktop/platform-tools/adb.exe；
           所有 adb 批处理脚本开头必须 export MSYS_NO_PATHCONV=1（否则 /data/... 会被 MSYS 改写成 Windows 路径）；
           给 adb 的本地文件路径一律用 C:/ 风格。
手机       小米14（houji），HyperOS 3.0.306 / Android 16；已 root：SukiSU Ultra（su 可用）；adb 序列号 <SERIAL>。
手表       Galaxy Watch7 SM-L310，One UI 8 Watch / Wear OS 16，无 root；蓝牙 MAC <WATCH_MAC>；Wear 节点 <DEVICE_ID>；
           无线 adb 地址与端口每次都会变 → 先 adb mdns services 重新发现（下文记作 <无线地址:端口>）。
应用版本   三星健康 7.00.6.011 ｜ 健康监测器(SHM) 1.5.2.002 ｜ Galaxy Wearable 2.2.70 ｜ Watch7 插件 2.2.15 ｜ 手表端 SHM 1.2.7.003(官方)
已装框架   Zygisk-Next(zygisk_rezygisk) + Vector v2.2(LSPosed 现名, zygisk_vector)
           + 模块 shm_watch7_fix(v5 自愈) + 伪装模块 com.arnold.spoofsamsung.Hook(v7/v8)
```

---

<a id="C1"></a>
## C1 · 手表↔手机数据通道时通时断，三星应用后台被省电库周期性杀

**影响范围**：所有三星应用的后台存活与手表通信 ｜ **严重程度**：P0

### ① 问题现象

- 手表↔手机数据通道**时通时断**；
- 三星应用后台**被杀**；
- 手表**唤不起手机**；
- 手表说『到手机上操作』但手机已打开了却**没数据**（注意区分：如果手机连页面都没拉起来，那更可能是 C2）。

特征：**周期性复发**——修好过一段时间（实测 15–30 分钟）又坏，这是 MIUI 云端周期性回滚配置导致的。

### ② 报错关键信息（原文代码块）

C1 没有显式报错日志，表现为「静默杀后台」；指纹在省电库配置数据库的内容里（以下为该库要点，非日志原文）：

```text
/data/data/com.miui.powerkeeper/databases/user_configure.db    （SQLITE，约 587 行）
表 userTable：列 pkgName（包名）、bgControl（后台管控值）
    bgControl = miuiAuto   → 限制后台
    bgControl = noRestrict → 放行

MIUI 云端周期性回滚（实测约 15–30 分钟一次）：删行重插（产生新 _id），
且只回滚部分包——把以下三个包从 noRestrict 改回 miuiAuto：
    com.samsung.wearable.watch7plugin
    com.samsung.accessory
    com.arnold.spoofsamsung.Hook
```

### ③ 根因分析

- MIUI powerkeeper（省电库）的每应用后台管控存放在 `/data/data/com.miui.powerkeeper/databases/user_configure.db`；把三星相关包设为 noRestrict 后，MIUI 云端会周期性（实测约 15–30 分钟）把配置**回滚**成 miuiAuto。
- 回滚方式是**删行重插**（产生新 _id），且**只回滚部分包**：`com.samsung.wearable.watch7plugin`、`com.samsung.accessory`、`com.arnold.spoofsamsung.Hook`——所以「只在系统 UI 里点一次允许」撑不过一个回滚周期。
- 进程被限制/杀掉后，`com.samsung.accessory` 也**不会自动复活**（它没有 launcher activity），手表数据通道随之断——所以修复方案里必须带 SAP 守护。

排查过程中沉淀的三个坑（演进教训）：

1. **Android 手机端没有 sqlite3 命令**——判据只能用 grep 计数，不要依赖 sqlite3；
2. **文件大小指纹会漏判**——实例：曾差 4096B，小于 4% 阈值 6881B 而漏判，必须改用内容计数；
3. **service.sh 演进教训**——`( ... ) &` 后台子 shell 会被 su 回收（实测开机 6h45m 零次执行）→ 必须常驻；间隔 900s 与云端回滚周期（≈15min）同频，约一半时间窗口被限 → 改 300s 并加 SAP 守护。

### ④ 快速定位要点

先看什么：距上次「修好」过了多久（15–30 分钟 ≈ 一个云端回滚周期）。查什么：noRestrict 计数、SAP 进程、8 个关键包的 bgControl。

```bash
export MSYS_NO_PATHCONV=1
ADB="%USERPROFILE%/Desktop/platform-tools/adb.exe"

# ── 第 1 步：判据——noRestrict 计数，应 ≥ 8（8 个关键包）；小于 8 = 已被云端回滚
# ⚠️ Android 手机端没有 sqlite3 命令，判据只能用 grep 计数，不要依赖 sqlite3
"$ADB" -s <SERIAL> shell su -c "grep -a -o noRestrict /data/data/com.miui.powerkeeper/databases/user_configure.db | wc -l"

# ── 第 2 步：SAP 进程在不在（无 launcher activity，被杀不自动复活）
"$ADB" -s <SERIAL> shell su -c "pidof com.samsung.accessory"

# ── 第 3 步（可选，PC 端）：拉库细看是哪几个包被回滚
"$ADB" -s <SERIAL> shell su -c "cat /data/data/com.miui.powerkeeper/databases/user_configure.db" > %USERPROFILE%/Desktop/user_configure.db
sqlite3 %USERPROFILE%/Desktop/user_configure.db "SELECT pkgName,bgControl FROM userTable WHERE pkgName IN ('com.mi.health','com.samsung.android.app.watchmanager','com.sec.android.easyMover','com.samsung.android.shealthmonitor','com.sec.android.app.shealth','com.samsung.wearable.watch7plugin','com.samsung.accessory','com.arnold.spoofsamsung.Hook');"
```

⚠️ **不要用文件大小当判据**——实例：曾差 4096B（< 4% 阈值 6881B）而漏判；只认 grep 计数。

### ⑤ 解决方案与操作步骤

**一次性手工修复**（五步，顺序执行）：

```bash
export MSYS_NO_PATHCONV=1
ADB="%USERPROFILE%/Desktop/platform-tools/adb.exe"
DB=/data/data/com.miui.powerkeeper/databases/user_configure.db

# ① 停掉 powerkeeper，防止它把旧配置写回
"$ADB" -s <SERIAL> shell su -c "am force-stop com.miui.powerkeeper"

# ② 用修正快照覆盖 user_configure.db
#    （若 KernelSU 模块已部署，快照就在 /data/adb/modules/<id>/user_configure.db，
#      可直接 cat 覆盖；否则先把快照 push 上去）
"$ADB" -s <SERIAL> push <快照本地路径> /data/local/tmp/user_configure.db
"$ADB" -s <SERIAL> shell su -c "cat /data/local/tmp/user_configure.db > $DB"

# ③ 修属主（powerkeeper 以 system 身份读写）
"$ADB" -s <SERIAL> shell su -c "chown system:system $DB"
# ④ 修权限
"$ADB" -s <SERIAL> shell su -c "chmod 660 $DB"
# ⑤ 清掉残留 journal，避免 sqlite 按旧事务回滚
"$ADB" -s <SERIAL> shell su -c "rm -f /data/data/com.miui.powerkeeper/databases/*-journal"
```

**快照要求**——必须含以下 8 个包的 `noRestrict`：

```text
com.mi.health
com.samsung.android.app.watchmanager
com.sec.android.easyMover
com.samsung.android.shealthmonitor
com.sec.android.app.shealth
com.samsung.wearable.watch7plugin
com.samsung.accessory
com.arnold.spoofsamsung.Hook
```

制作/更新快照：把手机上的库拉到 PC 端（见④），在 **PC 端**用 sqlite3 把这 8 个包的 bgControl 全部置为 noRestrict 后另存（Android 手机端没有 sqlite3 命令，改库必须在 PC 端做）。

**持久化——打包成 KernelSU 模块**（重启自动生效，替代手工修复）：

```text
/data/adb/modules/<id>/
├── module.prop          # 模块元信息（缺了 KernelSU 不识别）
├── system.prop          # 模块属性（按需，可留空）
├── service.sh           # 开机自动以 root 执行；内含 300s 常驻自愈循环 + SAP 守护
├── user_configure.db    # 修正快照（8 包 noRestrict）
└── self_heal.log        # 运行产物：每次检测与恢复的记录
```

`service.sh` 要点与骨架：

```sh
#!/system/bin/sh
# /data/adb/modules/<id>/service.sh —— 常驻自愈：300 秒一轮
MODDIR=${0%/*}
DB=/data/data/com.miui.powerkeeper/databases/user_configure.db
LOG="$MODDIR/self_heal.log"

while true; do
    # 1) 省电库自愈：noRestrict 计数 < 8 = 云端已回滚 → 恢复快照
    n=$(grep -a -o noRestrict "$DB" 2>/dev/null | wc -l)
    if [ "$n" -lt 8 ]; then
        am force-stop com.miui.powerkeeper
        cat "$MODDIR/user_configure.db" > "$DB"
        chown system:system "$DB"
        chmod 660 "$DB"
        rm -f /data/data/com.miui.powerkeeper/databases/*-journal
        echo "$(date) noRestrict=$n -> snapshot restored" >> "$LOG"
    fi

    # 2) SAP 守护：com.samsung.accessory 无 launcher activity，
    #    进程被杀后不会自动复活 → 每轮检查，不在就广播拉起
    if ! pidof com.samsung.accessory >/dev/null 2>&1; then
        am broadcast -a android.accessory.device.action.CONNECT \
            -n com.samsung.accessory/.receivers.SAFrameworkStartTriggerReceiver
        echo "$(date) SAP down -> broadcast to start" >> "$LOG"
    fi

    # 间隔必须 300s：900s 与云端回滚周期(≈15min)同频，约一半时间窗口被限
    sleep 300
done
```

两条硬性教训：

- 循环必须**常驻在 service.sh 主进程里**（必要时用 setsid 脱离会话）；**不能**写成 `( while ... done ) &`——后台子 shell 会被 su 回收（实测开机 6h45m 零次执行）。
- **pkill 坑**：运维时若要终止旧的自愈循环，不要写 `pkill -f service.sh`——会连自己这条 shell 一起杀（adb 立刻掉线）；必须写 `pkill -f "servic[e].sh"`（字符类打断自身命令行的匹配，但仍能命中真正的 service.sh 进程）。

### ⑥ 验证方式

```bash
export MSYS_NO_PATHCONV=1
ADB="%USERPROFILE%/Desktop/platform-tools/adb.exe"

# 1) noRestrict 计数恢复到 ≥ 8
"$ADB" -s <SERIAL> shell su -c "grep -a -o noRestrict /data/data/com.miui.powerkeeper/databases/user_configure.db | wc -l"

# 2) SAP 进程 pidof 有输出
"$ADB" -s <SERIAL> shell su -c "pidof com.samsung.accessory"

# 3) self_heal.log 应有每次检测与恢复的记录
"$ADB" -s <SERIAL> shell su -c "cat /data/adb/modules/<id>/self_heal.log"

# 4) 跑完至少一个云端回滚周期（≥ 30 分钟）后复查第 1) 步——计数仍 ≥ 8 才算真修复
```

配套的手表↔手机链路验证：手表触发一次同步，确认数据通道恢复、不再「时通时断」。

### ⑦ 预防措施

- 快照 + service.sh 打包成 KernelSU 模块（`/data/adb/modules/<id>/`，system.prop + service.sh），重启自动生效，不依赖手工修复。
- 自愈间隔固定 **300s**（不要用 900s），并保留 SAP 守护。
- 判据一律用 **grep 计数（≥8）**，不要用文件大小指纹；也不要依赖手机端 sqlite3（不存在）。
- 重建清单条目：刷机 / 恢复出厂 / 换机后，重新部署该模块，并连着重做 C2 的「后台弹出界面」授权。
- 更新快照在 PC 端用 sqlite3 做，改完重新覆盖并按⑤修属主/权限/清 journal。

---

<a id="C2"></a>
## C2 · 手表提示『到手机上操作』但手机毫无反应（后台弹出界面被静默拦截）

**影响范围**：所有『手表发起、手机承接』的流程（血压校准、ECG 条款、antioxidant 同步跳转） ｜ **严重程度**：P0

### ① 问题现象

- 手表提示『到手机上操作』但**手机毫无反应**——不是「打开了没数据」（那是 C1），而是连页面都没拉起来；
- Galaxy Wearable 提示『无法在手机上打开三星健康』；
- 只修 C1（省电库）**不够**：实测修完省电库后仍被拦，直到开了这个权限才放行。

### ② 报错关键信息（原文代码块）

logcat 指纹（被拦时）：

```text
MIUILOG- Permission Denied Activity : Intent { ... cmp=... } pkg : com.samsung.wearable.watch7plugin
result code=102    （task 从未创建）
```

### ③ 根因分析

- MIUI 独有的**后台活动启动限制**（系统 UI 名叫「后台弹出界面」）：后台进程 startActivity 拉界面时被**静默拒绝**，result code=102、task 从未创建——所以手机端毫无反应、没有任何可见报错。
- **与 powerkeeper 省电库是两级独立检查**：省电库管进程能不能活着（C1），这里管活着的后台进程能不能弹界面。只修 powerkeeper 不够（实测：修完省电库后仍被拦，直到开了这个权限才放行）。
- 它**没有标准 AppOps op 名**：`cmd appops set <pkg> ACTIVATE_BG_ACTIVITY` 报 `Unknown operation`——命令行改不了。
- 配置可能存在 MIUI 自家 LBE 库 `/data/data/com.lbe.security.miui/databases/permission_db`（表 package_permission_level，permission_data 是数字键 JSON）。对比样本：微信的 JSON 多一个键而被拦应用没有——但**未确证该键就是「后台弹出界面」**，直接改库有风险。
- 结论：**最可靠的修法是 UI 手点**（约 1 分钟）。

### ④ 快速定位要点

先看什么：现象分诊——手机「打开了但没数据」先查 C1（见 C1④）；手机「毫无反应、页面没拉起」查 C2。查什么：手表再触发一次，同时抓 logcat 看指纹。

```bash
export MSYS_NO_PATHCONV=1
ADB="%USERPROFILE%/Desktop/platform-tools/adb.exe"

"$ADB" -s <SERIAL> logcat -c
# 然后让手表再触发一次（手表 SHM 健康监测器里点『在手机上打开』）：
"$ADB" -s <SERIAL> logcat | grep -E "MIUILOG- Permission Denied|result code=102|shealthmonitor://"
```

判读：

- 命中 `MIUILOG- Permission Denied Activity ... pkg : com.samsung.wearable.watch7plugin` + `result code=102` → C2 拦截确认（task 从未创建）；
- 深链指纹：放行后 logcat 里会连发 deep link `shealthmonitor://shealthmonitor.samsung.com/...`（实测一次 48 个）——可用于确认放行已生效；
- 想看当前授权状态：设置 → 应用管理 → Galaxy Watch7 Manager → 权限，看「后台弹出界面」是否为「允许」。LBE 库的数字键未确证，不建议用改库的方式定位。

### ⑤ 解决方案与操作步骤

人工 UI 操作（约 1 分钟；无可靠命令行等价物）：

```text
设置 → 应用设置 → 应用管理 → 搜「Galaxy」
  → Galaxy Watch7 Manager → 权限 → 「后台弹出界面」→ 允许
  → 三星配件服务（如果有同一项）→ 也开
```

- 为什么不用命令行：该权限没有标准 AppOps op 名（`cmd appops set <pkg> ACTIVATE_BG_ACTIVITY` 报 Unknown operation）；LBE 库 permission_db 的数字键未确证，改库风险大于收益。
- ⚠️ UI 操作必须**真人手点**：MIUI 会吞合成触摸（见 C3），`input tap` 自动点不可靠。

### ⑥ 验证方式

```bash
export MSYS_NO_PATHCONV=1
ADB="%USERPROFILE%/Desktop/platform-tools/adb.exe"

"$ADB" -s <SERIAL> logcat -c
# 让手表再触发一次：手表 SHM（健康监测器）里点『在手机上打开』
"$ADB" -s <SERIAL> logcat | grep -E "shealthmonitor://|result code=102|MIUILOG- Permission Denied"
```

- **通过**：deep link `shealthmonitor://shealthmonitor.samsung.com/...` 连发（实测一次 48 个）；**不再出现** `result code=102`；手机端 SHM 被正常拉起；
- **不通过**：仍出现 `MIUILOG- Permission Denied ... pkg : com.samsung.wearable.watch7plugin` → 回到⑤检查两个应用的开关。

### ⑦ 预防措施

- **恢复出厂 / 系统重置后此权限必丢**——重建清单里必须包含这一步（人工手点，勿指望自动化代点）。
- 重建清单同时检查两个应用：**Galaxy Watch7 Manager**、**三星配件服务**。
- 排查习惯：遇到「手机无反应」先抓这条 logcat 指纹再动手，避免误当 C1 修（只修省电库修不动它）。

---

<a id="C3"></a>
## C3 · root 下 input tap 点了没反应、时灵时不灵（MIUI 吞合成触摸）

**影响范围**：所有 UI 自动化尝试 ｜ **严重程度**：P1

### ① 问题现象

- root 下 `input tap x y` **点了没反应**（uiautomator dump 能正常读 UI——dump 与注入是两套权限）；
- `input keyevent` 同样**不可靠**；
- 偶发生效，但**不可依赖**——不能把自动化流程押在「偶尔能点」上。

### ② 报错关键信息（原文代码块）

未开「USB 调试（安全设置）」时直接拒绝：

```text
SecurityException: Injecting input events requires the caller (or the source of the instrumentation, if any) to have the INJECT_EVENTS permission.
```

开了之后部分场景（如表单控件）仍可能不生效——此时**无报错**，点击被静默吞掉，只能靠 UI 状态对比发现。

### ③ 根因分析

- MIUI 特有限制：开发者选项里的「**USB 调试（安全设置）**」未开启时，拒绝注入输入事件（INJECT_EVENTS）——即使设备已 root（SukiSU Ultra，su 可用）、`input` 命令本身正常返回。
- 开启后仍有残留场景（如**表单控件**）不响应合成点击，机制未完全公开；因此任何关键 UI 操作都不能依赖合成触摸。
- 实测必须真人手点的操作：SHM 个人资料页的『保存』、数据权限弹窗的总开关、改出生日期触发校验。

### ④ 快速定位要点

先看什么：开发者选项里「USB 调试（安全设置）」是否已开——没开时 `input` 直接抛 SecurityException（见②）。查什么：点完立刻 uiautomator dump 对比目标元素状态；**状态没变 = 点击被吞**。

```bash
export MSYS_NO_PATHCONV=1
ADB="%USERPROFILE%/Desktop/platform-tools/adb.exe"

# 点击前 dump 一次
"$ADB" -s <SERIAL> shell uiautomator dump
"$ADB" -s <SERIAL> shell cat /sdcard/window_dump.xml > %USERPROFILE%/Desktop/before.xml

# input tap x y    ← 目标坐标

# 点击后再 dump 一次，对比目标元素（如按钮 enabled 是否翻转）
"$ADB" -s <SERIAL> shell uiautomator dump
"$ADB" -s <SERIAL> shell cat /sdcard/window_dump.xml > %USERPROFILE%/Desktop/after.xml
# PC 端 diff before.xml after.xml，或直接 grep 目标节点的 enabled/clickable 属性
```

判读：

- `input` 输出里出现 `SecurityException: Injecting input events requires ... INJECT_EVENTS permission.` → 「USB 调试（安全设置）」没开；
- 无报错但目标元素状态没变（如 enabled 仍为 false）→ 点击被吞 → 走⑤的降级路径（用户手点）。

### ⑤ 解决方案与操作步骤

① 开发者选项 → 「**USB 调试（安全设置）**」→ 打开（需登录小米账号）。

② **关键 UI 操作一律让用户手点**——实测：SHM 个人资料页的『保存』、数据权限弹窗的总开关、改出生日期触发校验，全都必须真人手指。

③ 自动化只负责『拉起页面 + 截图 + dump 读状态』，**不负责点**：

```bash
export MSYS_NO_PATHCONV=1
ADB="%USERPROFILE%/Desktop/platform-tools/adb.exe"

# 拉起页面（deep link 以 logcat 实抓到的完整 URI 为准，见 C2⑥）
"$ADB" -s <SERIAL> shell am start -a android.intent.action.VIEW -d "shealthmonitor://shealthmonitor.samsung.com/..."
# 截图
"$ADB" -s <SERIAL> exec-out screencap -p > %USERPROFILE%/Desktop/screen.png
# 读状态
"$ADB" -s <SERIAL> shell uiautomator dump
"$ADB" -s <SERIAL> shell cat /sdcard/window_dump.xml
# 点击环节 → 交给用户手点（附目标位置截图说明），点完回到④对比状态
```

### ⑥ 验证方式

- dump 对比**点击前后目标元素的状态变化**（如 `enabled=false → true`）——状态变了才算点击生效；
- 开了「USB 调试（安全设置）」后，`input tap` / `input keyevent` 不再抛 SecurityException；但表单类控件仍以真人手点为准，不因开关打开就改回自动化点击。

### ⑦ 预防措施

- 把『MIUI 吞合成触摸』写进重建清单的注意事项。
- 任何需要点 UI 的自动化步骤都要有**『用户手点』的降级路径**：自动化拉起页面 → 截图标注 → 用户手点 → dump 验证。
- 开发者选项初始化清单：「USB 调试」+「USB 调试（安全设置）」两项都要开（后者需登录小米账号）。
