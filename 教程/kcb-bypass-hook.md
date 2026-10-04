# KCB 绕过 Hook — 关键 smali 改动

本文档记录对 LSPosed 模块 `com.arnold.spoofsamsung.Hook` 的增量改动，用于让三星健康跳过 KCB 检查。

## 1. Hooker 类（新增 `h.smali`）

Hooker 走 `Chain.proceed()` 后强制返回 `Boolean.TRUE`（覆盖原返回值）：

```smali
.class public final Lh;
.super Ljava/lang/Object;
.source "ShealthChinaBuildHooker"

# interfaces
.implements Lio/github/libxposed/api/XposedInterface$Hooker;


# direct methods
.method public constructor <init>()V
    .registers 1

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method


# virtual methods
.method public final intercept(Lio/github/libxposed/api/XposedInterface$Chain;)Ljava/lang/Object;
    .registers 3

    invoke-interface {p1}, Lio/github/libxposed/api/XposedInterface$Chain;->proceed()Ljava/lang/Object;

    sget-object v0, Ljava/lang/Boolean;->TRUE:Ljava/lang/Boolean;

    return-object v0
.end method
```

## 2. Hook 安装方法（追加到 `SpoofSamsungModule.smali`）

```smali
.method private final hookShealthChinaBuild(Ljava/lang/ClassLoader;)V
    .registers 6

    :try_start_sh
    const-string v0, "fs90"

    const/4 v1, 0x0

    invoke-static {v0, v1, p1}, Ljava/lang/Class;->forName(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;

    move-result-object v0

    const-string v1, "u"

    const/4 v2, 0x0

    new-array v2, v2, [Ljava/lang/Class;

    invoke-virtual {v0, v1, v2}, Ljava/lang/Class;->getDeclaredMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;

    move-result-object v0

    invoke-virtual {p0, v0}, Lio/github/libxposed/api/XposedModule;->hook(Ljava/lang/reflect/Executable;)Lio/github/libxposed/api/XposedInterface$HookBuilder;

    move-result-object v0

    const-string v1, "shealth.china.build"

    invoke-interface {v0, v1}, Lio/github/libxposed/api/XposedInterface$HookBuilder;->setId(Ljava/lang/String;)Lio/github/libxposed/api/XposedInterface$HookBuilder;

    move-result-object v0

    sget-object v1, Lio/github/libxposed/api/XposedInterface$ExceptionMode;->PROTECTIVE:Lio/github/libxposed/api/XposedInterface$ExceptionMode;

    invoke-interface {v0, v1}, Lio/github/libxposed/api/XposedInterface$HookBuilder;->setExceptionMode(Lio/github/libxposed/api/XposedInterface$ExceptionMode;)Lio/github/libxposed/api/XposedInterface$HookBuilder;

    move-result-object v0

    new-instance v1, Lh;

    invoke-direct {v1}, Lh;-><init>()V

    invoke-interface {v0, v1}, Lio/github/libxposed/api/XposedInterface$HookBuilder;->intercept(Lio/github/libxposed/api/XposedInterface$Hooker;)Lio/github/libxposed/api/XposedInterface$HookHandle;

    const-string v0, "HOOK REGISTERED: shealth.china.build (fs90.u -> true)"

    const/4 v1, 0x4

    const/4 v2, 0x0

    invoke-direct {p0, v1, v0, v2}, Lcom/arnold/spoofsamsung/Hook/SpoofSamsungModule;->diagnosticLog(ILjava/lang/String;Ljava/lang/Throwable;)V

    :try_end_sh
    .catchall {:try_start_sh .. :try_end_sh} :catchall_sh

    return-void

    :catchall_sh
    move-exception v0

    const-string v1, "HOOK REGISTER FAILED: shealth.china.build"

    const/4 v2, 0x5

    invoke-direct {p0, v2, v1, v0}, Lcom/arnold/spoofsamsung/Hook/SpoofSamsungModule;->diagnosticLog(ILjava/lang/String;Ljava/lang/Throwable;)V

    return-void
.end method
```

## 3. `onPackageLoaded` 中追加的分支判断

在 `onPackageLoaded` 里、`TARGET_PACKAGES` 判断之前插入：

```smali
    # --- BEGIN shealth china-build hook (added) ---
    const-string v0, "com.sec.android.app.shealth"

    invoke-interface/range {p1 .. p1}, Lio/github/libxposed/api/XposedModuleInterface$PackageLoadedParam;->getPackageName()Ljava/lang/String;

    move-result-object v1

    invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :cond_sh_skip

    invoke-interface/range {p1 .. p1}, Lio/github/libxposed/api/XposedModuleInterface$PackageLoadedParam;->getDefaultClassLoader()Ljava/lang/ClassLoader;

    move-result-object v0

    invoke-direct {p0, v0}, Lcom/arnold/spoofsamsung/Hook/SpoofSamsungModule;->hookShealthChinaBuild(Ljava/lang/ClassLoader;)V

    :cond_sh_skip
    # --- END shealth china-build hook (added) ---
```

## 4. LSPosed 作用域配置（DB 直改）

作用域存储在 `/data/adb/lspd/config/modules_config.db`（SQLite），三张表：

```sql
modules      (module_pkg_name PRIMARY KEY, apk_path)
modules_state(module_pkg_name, user_id, enabled, scope_request_blocked)
scope        (module_pkg_name, app_pkg_name, user_id)
```

改动步骤：

1. `killall lspd` 停掉守护进程，避免写入竞争
2. 拉取 `modules_config.db` + `-wal`，用 Python `sqlite3` 打开（关闭时自动 checkpoint 合并 WAL）
3. 插入：

```sql
INSERT OR REPLACE INTO modules_state VALUES ('com.arnold.spoofsamsung.Hook', 0, 1, 0);
INSERT OR REPLACE INTO scope VALUES ('com.arnold.spoofsamsung.Hook', 'com.samsung.wearable.watch7plugin', 0);
INSERT OR REPLACE INTO scope VALUES ('com.arnold.spoofsamsung.Hook', 'com.sec.android.app.shealth', 0);
```

4. 推回、删除 `-wal` / `-shm`，修正权限与 SELinux 上下文（同目录为 `u:object_r:system_file:s0`）
5. 重启设备

## 5. 注意事项

- 模块重签名后，必须 `adb uninstall` 旧模块再安装新版（不同签名无法覆盖安装）。
- uber-apk-signer 每次生成随机临时 keystore，后续更新模块仍需走「卸载 → 重装」流程。
- 三星健康本体 APK 不要动：重签名会强制卸载重装，导致已登录账号与手表配对丢失。
