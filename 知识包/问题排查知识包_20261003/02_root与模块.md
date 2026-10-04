# 02 · root 与模块

> **B1 和 B4 是 P0**：B1 会让你以为"模块写坏了"，B4 会让你以为"属性改了没用"。

---

<a id="B1"></a>
## B1 ★ LSPosed 版本门槛：模块装上但完全不加载（P0）

**影响范围**：所有 LSPosed 模块的加载与生效 ｜ **严重程度**：P0

**现象**
- 伪装模块 APK 装好了、作用域也配了、重启了
- **但 logcat 里一条 hook 记录都没有**，功能完全没变
- **LSPosed 不报任何错** ← 最坑的地方

**报错关键信息**
无报错。只能通过"**缺少预期日志**"判断：
```
（期望）I/SpoofSamsung: ENTRY LOADED: process=com.samsung.android.shealthmonitor
（实际）什么都没有
```

**根因**
模块的 `META-INF/xposed/module.prop` 里写着：
```
minApiVersion=102   targetApiVersion=102
```
这是 **libxposed 新 API**。只有 **LSPosed 2.x / Vector 2.x** 认。
**LSPosed 1.9.2**（Xposed API 93 架构）不认 → **静默忽略该模块**。

**快速定位**（按顺序）
```bash
# ① 看模块声明的 API 版本
unzip -p <模块.apk> META-INF/xposed/module.prop

# ② 看 LSPosed 内核模块 id（判断是哪一代）
"$A" shell "su -c 'ls /data/adb/modules/'"
#   zygisk_lsposed  = 老 LSPosed（1.x）
#   zygisk_vector   = 新 Vector（2.x）✅
```
```bash
# ③ 装完后立刻抓日志，找"模块加载"字样
"$A" logcat -d | grep -aiE "LSPosedFramework|ENTRY LOADED"
```

**解决方案**
- 用 **Vector v2.2**（LSPosed 现名，由 JingMatrix 维护），模块 id `zygisk_vector`
- **不要用** `LSPosed-v1.9.2-*.zip`
- 安装顺序：**Zygisk 实现（Zygisk-Next）→ 重启 → Vector → 重启**
- 装完模块后**只需 force-stop 目标应用**，不必重启手机：
```bash
"$A" shell "su -c 'am force-stop com.samsung.android.shealthmonitor'"
```

**验证**
```bash
"$A" logcat -d | grep -a "SpoofSamsung"
# 应看到：ENTRY LOADED / HOOK REGISTERED: xxx
```

**预防**
- 换机/重装时**先确认 `ls /data/adb/modules/` 里有 `zygisk_vector`**
- 文档里写明"模块的 minApiVersion 决定了必须用哪代框架"

---

<a id="B2"></a>
## B2 重打包模块后无效果 / 怎么改模块

**影响范围**：模块修改 / 重打包 / 重装全流程 ｜ **严重程度**：P1

**现象**
改了 smali、重打包、装上了，但行为没变

**报错关键信息**
无报错。特征是"**安装与运行全程没有错误输出**"，只能靠"缺少预期日志"判断：
```
（期望）I/SpoofSamsung: SHM-MA: entered (v5c)     ← 版本标记日志（见预防）
（实际）什么都没有，或仍是旧版本的标记
```

**根因**（两类）
1. **改错了位置**：改的是"编译产物"而不是"当前运行的那份"（例：手上有 v7 源码，但手机装的是 v8）
2. **安装没生效**：没确认安装成功 / 没 force-stop 目标应用

**快速定位**
```bash
# 反编译"手机上正在跑的那份"，而不是手上的旧源码
"$A" shell pm path <模块包名>
"$A" pull <路径> ./current.apk
# 再 baksmali 它
```

**解决方案：完整构建流水线**
```bash
export MSYS_NO_PATHCONV=1
J='<JRE路径>\bin\java.exe'
CP='<jar1>;<jar2>;...'            # ⚠️ 必须 Windows 反斜杠风格分隔（工具链位置见 01·A5 与 09_附录）

# ① 反编译已装模块
"$J" -cp "$CP" org.jf.baksmali.Main d current.apk -o smali/

# ② 改 smali（加 hook / 改逻辑）

# ③ 汇编回 dex
"$J" -cp "$CP" org.jf.smali.Main a smali/ -o classes_new.dex

# ④ 重打包：替换 classes.dex + 去掉旧签名
python -c "
import zipfile
zin=zipfile.ZipFile('base.apk'); zout=zipfile.ZipFile('new_unsigned.apk','w',zipfile.ZIP_DEFLATED)
new=open('classes_new.dex','rb').read()
for it in zin.infolist():
    if it.filename.startswith('META-INF/') and it.filename.endswith(('.SF','.RSA','.DSA','.MF')): continue
    zout.writestr(it, new if it.filename=='classes.dex' else zin.read(it.filename))
zout.close()"

# ⑤ 签名 + 安装（同密钥可直接覆盖装，作用域不丢）
"$J" -jar uber-apk-signer.jar -a new_unsigned.apk -o signed --allowResign
"$A" install -r signed/new_unsigned-aligned-debugSigned.apk
"$A" shell "su -c 'am force-stop <目标应用>'"
```

**验证**
抓 logcat 看 hook 的注册日志；或直接看功能行为变化

**预防**
- 每次改动**在日志里打一条带版本标记的日志**（如 `SHM-MA: entered (v5c)`），一眼就能确认跑的是哪一版
- 保留原版 APK 作回滚

---

<a id="B3"></a>
## B3 uber-apk-signer 参数互斥

**影响范围**：签名步骤（B2 流水线第 ⑤ 步） ｜ **严重程度**：P2

**现象**
签名命令被拒，产不出签名 APK

**报错关键信息**
```
either provide out path or overwrite argument, cannot process both
usage: uber-apk-signer -a <file/folder> | -h | -v [--allowResign] ...
```

**快速定位**
- 复现时看命令行里是否**同时**出现 `-o <目录>` 与 `--overwrite`
- 或跑 `java -jar uber-apk-signer.jar --help` 对照 usage 逐个核对参数

**根因**
`-o <目录>` 与 `--overwrite` **不能同时给**

**解决方案**
```bash
# 二选一
"$J" -jar uber-apk-signer.jar -a x.apk -o signed --allowResign      # ✅ 输出到目录
"$J" -jar uber-apk-signer.jar -a x.apk --overwrite --allowResign    # ✅ 原地覆盖
```

**验证**
输出目录里出现 `*-aligned-debugSigned.apk`

**预防**
把签名命令固化进脚本，不手敲。

---

<a id="B4"></a>
## B4 ★ resetprop 改了但应用读不到：`Build.*` 在 zygote 冻结（P0）

**影响范围**：所有依赖 `Build.*` / 系统属性的伪装判断 ｜ **严重程度**：P0

**现象**
- `resetprop ro.product.manufacturer samsung` 执行成功、`getprop` 也读回 samsung
- **但目标应用里的 `Build.MANUFACTURER` 仍然是旧值** → 代码分支没变化

**报错关键信息**
无报错。特征是"**属性明明改了，应用行为没变**"。
可在 hook 里打一条日志把值打出来确认：
```
I/SpoofSamsung: Xiaomi          ← 期望 samsung，实际还是 Xiaomi
```

**根因**
`android.os.Build` 是**启动类**，它的静态字段在 **zygote 启动时初始化**，
之后通过 **COW 共享**给所有应用进程。
运行时改属性**不会**改变已经初始化好的 `Build.*` 静态字段。

**快速定位**
在目标进程里打印该字段（hook 打日志 / 或对比行为），**不要只看 `getprop`**

**解决方案**（三种，按代价排序）
1. **改 hook 逻辑**：不要依赖 `Build.*`，改成 hook 具体方法（本次最终方案）
2. **开机时注入**：让属性在 **zygote 启动前**就生效 → 用 KernelSU 模块的 `system.prop`（开机应用），而不是运行时 resetprop
3. 不要试图在运行时"骗过"已初始化的静态字段

**验证**
目标进程里的判断分支真的走了新路径（行为变化 + 日志）

**预防**
记住这条：**运行时 resetprop 只对"会重新读 prop 的代码"有效**；
`Build.*`、已缓存的系统服务字段一律无效。

---

<a id="B5"></a>
## B5 KernelSU 模块安装与生效

**影响范围**：KernelSU 模块的安装与开机生效 ｜ **严重程度**：P1

**现象**
- 把模块文件推到 `/data/adb/modules/` 后没生效
- 或想知道"能不能做成 zip 一键装"

**报错关键信息**
多数情况**无报错**。判据看安装 / 生效状态：
```
Module installed successfully!      ← ksud module install 成功的期望输出
（模块目录里出现空文件 update = 已装待重启）
```
未生效时：`ksud module list` 里 enabled 未置 true；`getprop <模块注入的属性>` 读不到。

**根因**
KernelSU 模块是**两阶段安装**：装到 `modules_update/`，**重启后**才搬到 `modules/` 生效

**快速定位**
```bash
"$A" shell "su -c 'ls -la /data/adb/modules/<模块id>/'"          # 现役
"$A" shell "su -c 'ls -la /data/adb/modules_update/<模块id>/'"   # 待生效
"$A" shell "su -c 'ksud module list'"                            # enabled / update 状态
```
> 看到模块目录里有个空文件 `update` = 已装待重启

**解决方案**

**方式一：一键安装 zip（推荐给最终用户）**
```bash
# 模块 zip 结构（Magisk/KernelSU 通用）
module.prop
system.prop            # 开机注入的属性
service.sh             # 开机执行的脚本
<其他数据文件>
customize.sh           # 解包后自动执行（设权限）
META-INF/com/google/android/update-binary
META-INF/com/google/android/updater-script   # 内容为 #MAGISK
```
```bash
# 安装（= 管理器里点"从本地安装"的同一路径）
"$A" push module.zip /data/local/tmp/m.zip
"$A" shell "su -c 'ksud module install /data/local/tmp/m.zip'"
# → 期望输出 "Module installed successfully!"
"$A" reboot        # 必须重启：system.prop 开机注入，service.sh 开机拉起
```

**方式二：手动推（调试用）**
```bash
K=/data/adb/modules/<模块id>
"$A" shell "su -c 'mkdir -p $K'"
"$A" push module.prop system.prop service.sh <数据文件> $K/    # ⚠️ 本地路径用 C:/ 风格
"$A" shell "su -c 'chmod 755 $K/service.sh; chown -R root:root $K'"
"$A" reboot
```

**验证**
```bash
"$A" shell "su -c 'ksud module list'"        # enabled=true
"$A" shell getprop <模块注入的属性>          # 属性已生效
"$A" shell "su -c 'cat /data/adb/modules/<模块id>/<日志文件>' | tail -5"
```

**预防**
- **service.sh 的坑**（都实际踩过）：
  | 写法 | 结果 |
  |---|---|
  | `( ... ) &` 后台子 shell | ❌ 父脚本退出后被回收，**循环从未运行** |
  | 依赖 `sqlite3` 命令 | ❌ Android 没有该命令 |
  | 用文件大小做指纹 | ❌ 小差异漏判 |
  | `setsid` 常驻 + 计数判据 | ✅ 可用 |
- **`pkill -f service.sh` 会连自己的 shell 一起杀**（adb 立刻掉线）；要写 `pkill -f "servic[e].sh"`
