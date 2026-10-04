# MIUI powerkeeper 拦截「手表 → 手机」应用唤起

> **现象**：手表上弹出「确定」→ 点击 → 手表提示「到手机上（操作）」→ **手机毫无反应**。
> **结论**：MIUI 自有省电框架 `com.miui.powerkeeper` 把发起的 App 判为「智能省电」，
> 拦掉了它发起的后台 Activity 启动（BAL）。AOSP 的 Doze 白名单对此**完全无效**。

---

## 1. 现象与日志

`logcat` 抓到（单次抓取内重复 **21 次**）：

```
ActivityStarterImpl: MIUILOG- Permission Denied Activity :
  Intent { act=android.intent.action.VIEW cat=[android.intent.category.BROWSABLE]
           dat=shealthmonitor://shealthmonitor.samsung.com/... flg=0x10000000 xflg=0x4
           cmp=com.samsung.android.shealthmonitor/.ui.activity.MainActivity }
  pkg : com.samsung.wearable.watch7plugin  uid : 10483  tuid : 10423
ActivityTaskManager: START ... (BAL_ALLOW_ALLOWLISTED_COMPONENT) result code=102
WindowManager: ActivityRecord{... u0 ... t-1}      ← task -1，从未创建
```

- `result code=102` = `START_ABORTED`
- `t-1` = 从未创建 task

## 2. 调用链

```
手表 (Wear OS)
  └─ Galaxy Wearable 插件被 wakelock 唤醒 (RmIntentMsgListener)
      └─ com.samsung.wearable.watch7plugin (uid 10483)
          └─ startActivity(shealthmonitor:// → shealthmonitor/.ui.activity.MainActivity)
              └─ ✗ 被 MIUI BAL 策略拒绝
```

**关键**：deep link 链路本身完好。用 shell 身份执行同一条命令可秒开：

```bash
adb shell "am start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE \
  -d 'shealthmonitor://shealthmonitor.samsung.com/start' \
  -n com.samsung.android.shealthmonitor/.ui.activity.MainActivity -f 0x10000000"
# → ResumedActivity: com.samsung.android.shealthmonitor/.home.ui.activity.SHealthMonitorMainActivity
```

所以问题**只在调用方**：`com.samsung.wearable.watch7plugin` 被 MIUI 限制。

## 3. 根因：MIUI powerkeeper ≠ AOSP Doze

```bash
adb shell dumpsys deviceidle whitelist | grep samsung
user,com.samsung.android.app.watchmanager,10482
user,com.samsung.android.shealthmonitors,10548
user,com.samsung.android.shealthmonitor,10423
user,com.samsung.accessory,10482
user,com.samsung.wearable.watch7plugin,10483
```

**5 个包全在 AOSP Doze 白名单里，照样被拦。** MIUI 用自有 `com.miui.powerkeeper` 判定，
不读 `deviceidle` 白名单。

策略库：`/data/data/com.miui.powerkeeper/databases/user_configure.db`（属主 `system:system 660`）

```sql
CREATE TABLE userTable (
  _id INTEGER PRIMARY KEY AUTOINCREMENT,
  userId INTEGER NOT NULL DEFAULT 0,
  pkgName TEXT NOT NULL,
  lastConfigured INTEGER,
  bgControl TEXT NOT NULL DEFAULT 'miuiAuto',   -- noRestrict | miuiAuto
  bgLocation TEXT,
  bgDelayMin INTEGER,
  UNIQUE (userId, pkgName)
);
```

改动前实测：

| pkgName | bgControl |
|---|---|
| com.samsung.android.app.watchmanager | noRestrict（用户已设） |
| com.samsung.android.shealthmonitor | noRestrict（用户已设） |
| com.samsung.android.shealthmonitors | noRestrict（用户已设） |
| com.sec.android.app.shealth | noRestrict |
| **com.samsung.wearable.watch7plugin** | **miuiAuto** ← 元凶 |
| **com.samsung.accessory** | **miuiAuto** ← 元凶 |

## 4. 为什么在 UI 里设不了

`com.samsung.accessory` **没有任何 Activity**：

```bash
adb shell monkey -p com.samsung.accessory -c android.intent.category.LAUNCHER 1
# → No activities found to run
```

MIUI 的「应用设置 → 省电策略」页由 Activity 驱动渲染，**无 Activity 的 App 不出现该入口**。
所以「这个应用没有省电策略选项」不是 bug，是 MIUI 的实现方式 → 只能从 root 层改库。

## 5. 修复步骤

手机无 `sqlite3`，必须 pull 到 PC 改再 push。

```bash
export MSYS_NO_PATHCONV=1
A="%USERPROFILE%/Desktop/platform-tools/adb.exe -s <SERIAL>"

# ① 备份
$A shell "su -c 'cp -a /data/data/com.miui.powerkeeper/databases/user_configure.db \
  /sdcard/uc_backup_20261001.db'"

# ② 停 powerkeeper 后拉库（避免 -wal 未落盘）
$A shell "su -c 'am force-stop com.miui.powerkeeper; sleep 1; \
  cp /data/data/com.miui.powerkeeper/databases/user_configure.db /sdcard/uc.db; \
  chmod 666 /sdcard/uc.db'"
$A pull /sdcard/uc.db work/uc.db
```

③ PC 端（Python）：

```python
import sqlite3, time
c = sqlite3.connect('work/uc_new.db')
for p in ['com.samsung.wearable.watch7plugin', 'com.samsung.accessory']:
    c.execute("update userTable set bgControl='noRestrict', lastConfigured=?, "
              "bgLocation=NULL, bgDelayMin=NULL where pkgName=?", (int(time.time()*1000), p))
c.commit()
```

④ 写回（**必须 chown/chmod，否则 powerkeeper 读写失败**）：

```bash
$A push work/uc_new.db /sdcard/uc_new.db
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
$A pull /sdcard/v.db work/v.db     # Python 读 bgControl 仍为 noRestrict 即成功
```

改后结果：**7 个三星包全部 `noRestrict`**，8 秒后复核未被回滚。

## 6. 附带发现：Galaxy Wearable 被 MIUI 杀死

```bash
$A shell "ps -A -o PID,NAME | grep -i samsung"
# 修复前：只有 watch7plugin(:persistent) / accessory / shealthmonitor(s)
#         ❌ 完全没有 com.samsung.android.app.watchmanager
```

手动拉起：

```bash
$A shell "am start -n com.samsung.android.app.watchmanager/.setupwizard.SetupWizardWelcomeActivity"
```

恢复后 3 个进程：`watchmanager` / `:remote` / `:contentprovider`，
主界面正常渲染并**实时读出手表电量 51%**。

→ 说明「三星健康 ↔ 手表」数据通道本身是好的，**断链唯一原因是进程被 MIUI 杀**。

## 7. 附带发现：核心需求其实早已通过

`/data/data/com.sec.android.app.shealth/shared_prefs/*.xml`：

```
last_connected_device = {"btAddress":"<WATCH_MAC>",
  "lastConnectedTime":1790816747220,
  "node":{"model_name":"Galaxy Watch7","model_number":"SM-L310",
          "device_id":"<DEVICE_ID>","data_sync_support":true,
          "protocol_version":4.51,"bluetooth_name":"Galaxy Watch7 (PGLX)"}}
dp_wearable_last_data_sync_info_<DEVICE_ID> = {"logging_time":1790816138689,"HRM":...}
dp_wearable_defaultTile_<DEVICE_ID> = tracker.pedometer,tracker.sleep,tracker.floor,...
sleep_coaching_wearable_paired / home.connected.wearables
```

时间戳换算：

| 键 | 时间 |
|---|---|
| `lastConnectedTime` | 2026-10-01 09:05:47 |
| `dp_wearable_last_data_sync_info_<DEVICE_ID>` | 2026-10-01 08:55:38 |

三星健康首页实测渲染：步数 729 / 睡眠得分 57 / 身体成分 73.0kg·29.3kg·25.1%。

## 8. 与 SAP（ECG/血压）的区别

本次修复解决的是「**手机端 App 打不开**」，**不代表 SAP 通道已通**：

```
SAFrameworkConnection: No connected accessories found. Returning ....
SAAgentV2: FindPeer response received → Peer Not Found(1793)
S HealthMonitor - BPAgent/ECGAgent: [SAP_CALLBACK] FINDPEER_DEVICE_NOT_CONNECTED
Profile: SapService → STATE_LISTENING / ROLE_LISTEN / RFCOMM / SAP
```

`com.samsung.accessory/databases/` 为空 → 手表 SAP 客户端从未连过手机；
手机端 SAP server 一直在监听（RFCOMM ch11）。
→ 手表端需打开三星健康监测器触发 agent 注册。**此项只影响 ECG/血压，与睡眠/心率上屏无关。**

## 9. 变更清单

| 项 | 位置 |
|---|---|
| 省电库备份 | 设备 `/sdcard/uc_backup_20261001.db` |
| 省电库改动 | `com.samsung.wearable.watch7plugin` / `com.samsung.accessory` → `noRestrict` |
| appop 补充 | `SYSTEM_ALERT_WINDOW=allow`（watch7plugin / watchmanager / shealth） |
| 本地副本 | `work/uc2.db`、`work/uc2_new.db`、`work/verify.db`、`work/v2.db` |
