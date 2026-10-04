#!/system/bin/sh
# ============================================================
# shm_watch7_fix · service.sh  (v5 — 常驻自愈 + SAP 守护)
#
# 演进史（四个真 bug，逐个修掉）：
#  v1  ( ... ) & 后台子shell  → KSU 父脚本退出后子进程被回收，
#                             循环从未存活（实测开机 6h45m 零次执行）
#  v2  前台死循环            → 判据依赖 sqlite3 命令，手机根本没有 → 逻辑失效
#  v3  改用文件大小做指纹     → 差 4096B < 4%阈值(6881B)，漏判，仍失效
#  v4  setsid 常驻 + noRestrict 计数判据   ✅ 判据可靠，但仍与云端回滚同频拉锯
#  v5  本版：解决 v4 暴露的第二个问题
#     · 间隔 900s → 300s：云端回滚周期实测 ≈15 分钟，与 900s 几乎同频，
#       导致约一半时间窗口 SAP 是被限制的（self_heal.log 17:21:59 / 17:37:00 两次实证）
#     · 新增 SAP 进程守护：com.samsung.accessory 改成 noRestrict 后进程也不会自动复活，
#       必须显式触发（它没有任何 launcher activity），这里每轮检查并拉起
# ============================================================

MODDIR=$(dirname "$0")
DB=/data/data/com.miui.powerkeeper/databases/user_configure.db
SNAP="$MODDIR/user_configure_fixed.db"
LOG="$MODDIR/self_heal.log"
INTERVAL=300
EXPECT_NO_RESTRAINT=8      # 快照中 noRestrict 的出现次数
SAP_PKG="com.samsung.accessory"
SAP_RECV="com.samsung.accessory/.receivers.SAFrameworkStartTriggerReceiver"

log() {
  echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"
}

# 当前 DB 里 noRestrict 出现次数
count_no_restrict() {
  [ -f "$DB" ] || { echo 0; return; }
  grep -a -o 'noRestrict' "$DB" 2>/dev/null | wc -l
}

apply_snapshot() {
  [ -f "$DB" ] || { log "FAIL DB 不存在"; return 1; }
  [ -f "$SNAP" ] || { log "FAIL 快照不存在"; return 1; }
  am force-stop com.miui.powerkeeper 2>/dev/null
  sleep 1
  if cp "$SNAP" "$DB"; then
    chown system:system "$DB"
    chmod 660 "$DB"
    rm -f "$DB-journal"
    log "OK 已恢复快照 (noRestrict=$(count_no_restrict))"
    return 0
  fi
  log "FAIL 覆盖失败"
  return 1
}

# 守护 SAP 传输进程：没有它，所有手表↔手机消息都发不出去
ensure_sap() {
  if pidof "$SAP_PKG" >/dev/null 2>&1; then
    return 0
  fi
  am broadcast -a android.accessory.device.action.CONNECT -n "$SAP_RECV" >/dev/null 2>&1
  sleep 3
  if pidof "$SAP_PKG" >/dev/null 2>&1; then
    log "OK SAP 已拉起 (pid $(pidof $SAP_PKG))"
  else
    log "WARN SAP 拉起失败，检查 MIUI 自启动是否给 $SAP_PKG 开了"
  fi
}

log "==== service.sh v5 启动 (pid $$) ===="
log "判据: noRestrict 出现次数 应 = $EXPECT_NO_RESTRAINT，当前 = $(count_no_restrict)"

ensure_sap
sleep 180

while true; do
  n=$(count_no_restrict)
  if [ "$n" -lt "$EXPECT_NO_RESTRAINT" ]; then
    log "检测到回滚 (noRestrict=$n < $EXPECT_NO_RESTRAINT)，恢复中"
    apply_snapshot
  fi
  ensure_sap
  sleep $INTERVAL
done
