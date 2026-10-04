#!/usr/bin/env bash
# =============================================================================
# build_module.sh — 从 smali 源码重建打过补丁的 LSPosed 模块
#   （KCB 绕过 + SHM 入口改道 + SHM 地区伪装）
#
# 前置依赖（见 docs/SHM_Watch7_可复刻手册.md §1）：
#   - JDK 17（java 可执行）
#   - smali / baksmali 2.5.2 及依赖 jar
#   - uber-apk-signer（可选，用于签名；也可用 apksigner）
#   - python3（用于重打包 zip）
#
# 用法：
#   JAVA=/path/to/java \
#   SMALI_DIR=/path/to/smali/jars \
#   SIGNER=/path/to/uber-apk-signer.jar \
#   ./tools/build_module.sh
#
# 输入：
#   artifacts/module/spoof_module_original.apk   （原始模块，作为 APK 外壳：manifest/资源/xposed 元数据）
#   artifacts/module/smali_v7/                   （补丁后的完整 smali 源码）
# 输出：
#   build/spoof_v7_unsigned.apk                  （未签名）
#   build/spoof_v7_signed.apk                    （已签名，可直接 adb install）
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- 可配置项（用环境变量覆盖）----------------------------------------------
JAVA="${JAVA:-java}"
SMALI_DIR="${SMALI_DIR:-$REPO_ROOT/apk/smali}"          # 存放 smali/baksmali 及依赖的目录
SIGNER="${SIGNER:-$REPO_ROOT/apk/uber-apk-signer.jar}"  # 可留空跳过签名
BASE_APK="${BASE_APK:-$REPO_ROOT/artifacts/module/spoof_module_original.apk}"
SRC_SMALI="${SRC_SMALI:-$REPO_ROOT/artifacts/module/smali_v7}"
WORK="${WORK:-$REPO_ROOT/build}"
PYTHON="${PYTHON:-python3}"

# 作用域（模块生效的包）
SCOPE_PKGS="${SCOPE_PKGS:-com.samsung.wearable.watchuniteplugin
com.samsung.wearable.watch7plugin
com.sec.android.app.shealth
com.samsung.android.shealthmonitor}"

mkdir -p "$WORK"

# ---- 1) 组装 classpath（自动识别 Windows ';' 与非 Windows ':' 分隔符）--------
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) SEP=';' ;;
  *)                    SEP=':' ;;
esac
CP=""
for j in smali-2.5.2.jar dexlib2-2.5.2.jar util-2.5.2.jar \
         guava-27.1-android.jar jcommander-1.64.jar antlr-runtime-3.5.2.jar \
         stringtemplate-3.2.1.jar antlr-3.5.2.jar failureaccess-1.0.1.jar; do
  CP="${CP}${SMALI_DIR}/${j}${SEP}"
done
CP="${CP%?}"   # 去掉末尾分隔符

echo "[1/4] 汇编 smali -> classes.dex"
"$JAVA" -Xmx2g -cp "$CP" org.jf.smali.Main a "$SRC_SMALI" -o "$WORK/classes_new.dex"

echo "[2/4] 重打包：替换 classes.dex + 重写 scope.list，剔除旧签名"
BASE_APK="$BASE_APK" SRC_APK="$WORK/spoof_v7_unsigned.apk" \
  NEW_DEX="$WORK/classes_new.dex" SCOPE_PKGS="$SCOPE_PKGS" \
  "$PYTHON" - <<'PYEOF'
import zipfile, os
src = os.environ["BASE_APK"]; dst = os.environ["SRC_APK"]
newdex = open(os.environ["NEW_DEX"], "rb").read()
scope = (os.environ["SCOPE_PKGS"].strip() + "\n").encode()
zin = zipfile.ZipFile(src)
zout = zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED)
for item in zin.infolist():
    name = item.filename
    if name.startswith("META-INF/") and name.endswith((".SF", ".RSA", ".DSA", ".MF")):
        continue                                   # 剔除旧签名
    if name == "classes.dex":
        zout.writestr(item, newdex); print("  replaced classes.dex ->", len(newdex), "bytes"); continue
    if name == "META-INF/xposed/scope.list":
        zout.writestr(item, scope); print("  replaced scope.list"); continue
    zout.writestr(item, zin.read(name))
zout.close()
print("  built", dst, os.path.getsize(dst), "bytes")
PYEOF

echo "[3/4] 签名"
if [ -n "$SIGNER" ] && [ -f "$SIGNER" ]; then
  # 注意：uber-apk-signer 1.3.0 不允许同时给 --out 和 --overwrite
  #（会报 "either provide out path or overwrite argument, cannot process both"）
  "$JAVA" -jar "$SIGNER" --apks "$WORK/spoof_v7_unsigned.apk" \
          --out "$WORK/signed" --allowResign
  echo "  已签名: $WORK/signed/"
else
  echo "  跳过（未找到 SIGNER）→ 你可用 apksigner，或直接把未签名 APK 手动签名"
fi

echo "[4/4] 完成。安装："
echo "  adb uninstall com.arnold.spoofsamsung.Hook   # 重签名后必须卸载旧版"
echo "  adb install -r <signed apk>"
echo "  重启设备后在 LSPosed 中确认模块已启用且作用域为上面 4 个包。"
