# shm_watch7_fix — KernelSU / Magisk 模块（持久化）

把三条「重启就丢」或「会被系统杀」的修复固定下来：

1. **CSC 属性**（`system.prop`）：`ro.csc.*` = XXV/VN，让 SHM 的地区判定走越南分支。
2. **powerkeeper 省电库守护**（`service.sh`）：MIUI 会周期性把三星相关包改回 `miuiAuto`，
   导致它们被后台冻结（表现为「手表有数据但手机没反应」）。`service.sh` 每 5 分钟检测一次，
   发现回滚就覆盖回快照。
3. **SAP 传输层守护**（同一脚本的 `ensure_sap()`）：`com.samsung.accessory` 是手表↔手机消息的
   传输层，它**没有任何 launcher activity**，改成 `noRestrict` 后**也不会自动复活进程**，
   必须显式发广播触发。脚本每轮检查一次，死了就拉起。

## ⚠️ `user_configure_fixed.db` 必须自建

`service.sh` 依赖同目录下的 `user_configure_fixed.db` 快照。`artifacts/` 与 `oneclick/ksu_module/`
里附带的那份是**本机（小米 14 / MIUI 3.0.306）**的产物，**其他机器必须自建**：

```bash
export MSYS_NO_PATHCONV=1
A="adb -s <序列号>"
# 1) 先在「手机管家 → 省电策略」里把下列包设为"无限制"，或先跑 tools/shm_watch7_doctor.sh --fix
#    com.samsung.wearable.watch7plugin
#    com.samsung.wearable.watchuniteplugin
#    com.samsung.accessory
#    com.samsung.android.app.watchmanager
#    com.samsung.android.shealthmonitor
#    com.sec.android.app.shealth
#    com.arnold.spoofsamsung.Hook
# 2) 确认计数（健康态应为 8）
$A shell "su -c 'grep -a -o noRestrict /data/data/com.miui.powerkeeper/databases/user_configure.db | wc -l'"
# 3) 导出
$A shell "su -c 'am force-stop com.miui.powerkeeper; sleep 1; \
  cp /data/data/com.miui.powerkeeper/databases/user_configure.db /sdcard/fixed.db; \
  chmod 666 /sdcard/fixed.db'"
$A pull /sdcard/fixed.db ./user_configure_fixed.db
```

> 若计数不是 8，用 `sqlite3` 打开 `user_configure_fixed.db` 执行
> `UPDATE userTable SET bgControl='noRestrict' WHERE pkgName IN (上面的包名)`，
> 再把 `service.sh` 里的 `EXPECT_NO_RESTRAINT` 改成你实际的健康态计数。

## 安装

```bash
adb shell "su -c 'mkdir -p /data/adb/modules/shm_watch7_fix'"
adb push module.prop system.prop service.sh user_configure_fixed.db /data/adb/modules/shm_watch7_fix/
adb shell "su -c 'chmod 755 /data/adb/modules/shm_watch7_fix/service.sh; chown -R root:root /data/adb/modules/shm_watch7_fix'"
adb reboot          # 必须重启：system.prop 由内核在开机时应用，service.sh 由 Zygisk 拉起
```

**验证**：
```bash
adb shell "su -c 'ps -A -o PID,PPID,ARGS | grep shm_watch7 | grep -v grep'"
# 期望：<pid>  1  sh /data/adb/modules/shm_watch7_fix/service.sh
#        ↑ PPID=1 表示已 setsid 脱离会话，不会被父脚本回收
adb shell "su -c 'cat /data/adb/modules/shm_watch7_fix/self_heal.log'"
```

## 卸载

```bash
adb shell "su -c 'pkill -f \"servic[e].sh\"'"      # ⚠️ 见下方踩坑
adb shell "su -c 'rm -rf /data/adb/modules/shm_watch7_fix'"
adb reboot
```

> ⚠️ **不要写 `pkill -f service.sh`** —— 它会匹配到 `su -c` 自身的命令行，
> 杀掉自己的 shell，**adb 立刻掉线**。必须用 `servic[e].sh` 这种不自匹配的写法。

## 配置项

| 变量 | 默认 | 含义 | 调整建议 |
|---|---|---|---|
| `INTERVAL` | `300` | 自愈轮询间隔（秒） | 云端回滚频繁（表现为 noRestrict 长期 < 8）可降到 `180` |
| `EXPECT_NO_RESTRAINT` | `8` | 健康态 noRestrict 出现次数 | 换 ROM / 换包列表后需重算 |
| `DB` | `/data/data/com.miui.powerkeeper/databases/user_configure.db` | 目标库 | 非 MIUI 需改 |
| `SNAP` | `$MODDIR/user_configure_fixed.db` | 快照 | 每台机不同 |
| `SAP_PKG` | `com.samsung.accessory` | 要守护的传输层 | 换机型可能改 |

## 副作用（必读）

- **整库覆盖**：`service.sh` 是**整库覆盖**。每 5 分钟一次，
  会把你在这期间对其他 App 做的省电设置**一并冲掉**。
  不接受的话把 `INTERVAL` 调大，或只保留 `system.prop`（CSC 部分）手动维护 powerkeeper。
- **`system.prop` 是地区伪装**：只设三条 `ro.csc.*`，不与三星账号/风控直接交互，
  但属于"伪装地区"，是否接受由你判断。
- **需要 root**：复制与 chmod 都需 root。

## 版本演进史（别退回老版本）

| 版本 | 写法 | 结果 |
|---|---|---|
| v1 | `( ... ) &` 后台子 shell | ❌ KSU 父脚本退出后子进程被回收，**开机 6h45m 零次执行** |
| v2 | 前台死循环 | ❌ 判据依赖 `sqlite3` 命令，手机根本没这命令 |
| v3 | 文件大小做指纹 | ❌ 差 4096B < 4% 阈值（6881B），漏判 |
| v4 | `setsid` + `noRestrict` 计数判据 | ⚠️ 判据可靠，但 900s 间隔与云端回滚周期(~15min)同频，约一半时间 SAP 是被限的 |
| **v5** | 300s 间隔 + `ensure_sap()` | ✅ 当前版本 |

`service.sh` 与 `service_v5.sh` 内容相同（前者是安装时用的文件名，后者留档）。

## 文件说明

| 文件 | 作用 |
|---|---|
| `module.prop` | 模块元信息（id/name/version/description） |
| `system.prop` | 开机自动应用：`ro.csc.sales_code=XXV`、`ro.csc.countryiso_code=VN`、`ro.csc.iso_code=VN` |
| `service.sh` | 开机常驻（`setsid`），每 300s 恢复 powerkeeper 快照 + 守护 SAP 进程 |
| `service_v5.sh` | v5 原件留档（内容同 `service.sh`） |
| `user_configure_fixed.db` | **需自建**（见上）；`oneclick/ksu_module/` 里有一份本机版可参考 |
