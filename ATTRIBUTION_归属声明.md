# 归属与来源声明 / Attribution

> 本仓库**不含任何二进制文件**。所有内容为技术文档，
> 使用者需自行获取软件包并自行实现所需模块。

---

## 一、本仓库提供的内容

| 组成 | 性质 |
|---|---|
| `教程/` 5 份 | 纯 Markdown，技术原理与操作流程 |
| `知识包/` 10 份 | 纯 Markdown，故障排查记录（24 个问题） |
| `README.md` | 流程说明 |
| 本文件 | 声明 |

**零二进制、零安装包、零脚本。**

---

## 二、不在本仓库提供的东西

| 类别 | 具体 | 原因 |
|---|---|---|
| 三星应用 | 四个官方 APK | **三星版权**，无再分发授权 |
| boot 镜像 | `init_boot.img` 等 | 含设备厂商版权内容 |
| 第三方 root 工具 | KernelSU / Zygisk Next / Vector 等 | 各自有独立分发渠道与许可 |
| Xposed 模块 | 预编译 APK 或反编译源码 | 见下节 |
| 工具链 | JDK / smali / uber-apk-signer | 各自有独立分发渠道 |

### 获取途径

| 类别 | 途径 |
|---|---|
| 三星应用（国内） | 应用宝搜包名 |
| 三星应用（国外） | Galaxy Store / Play Store |
| 三星应用（最可靠） | 自己的三星设备 `adb pull $(pm path <包名>)` |
| KernelSU / Zygisk Next / Vector | 各自官方 GitHub Releases |
| JDK / smali / signer | 各自官网 |

---

## 三、第三方模块的情况

### 已知事实

网上流传一个用于 Galaxy Wearable 系应用的 Xposed 模块，
包名 `com.arnold.spoofsamsung.Hook`，功能描述为
「Spoof Samsung device info for Galaxy Wearable apps」。

本仓库对其来源做过取证，结论如下：

| 检查项 | 结果 |
|---|---|
| `classes.dex` 内 author / license / copyright / github 字符串 | **0 条** |
| `resources.arsc` 内作者信息 | **0 条**，仅一句功能描述 |
| 包内 `LICENSE` 文件 | **无** |
| GitHub `search/code` `"com.arnold.spoofsamsung"` | **0 命中** |
| GitHub `search/code` `spoofsamsung` | 9 条，全部无关（Vesper-OS、nmap 脚本等） |
| GitHub `search/repositories` `spoofsamsung` | **0 命中** |
| GitHub `search/repositories` `spoof samsung xposed` | **0 命中** |

### 结论

**原作者未知，原许可未知。**

按著作权法默认规则，未声明许可的作品保留所有权利，
他人不得修改或再分发；反编译本身也可能违反原作品 EULA。

**因此本仓库不提供、不分发该模块，也不分发其任何修改版。**

### 如果你正是原作者

请通过 GitHub 仓库 owner 的主页联系。届时可以：

1. 在所有文档中补上你的署名与许可声明
2. 把你的仓库地址、Issue 链接、联系方式写进 README
3. 由你决定是否接受本项目的分析结论

---

## 四、符号名引用说明

README 与教程中提到的以下内容，属于**对第三方软件的分析结果**，
不构成对任何作品的复制或分发：

- 包名（`com.samsung.android.healthmonitor` 等）—— 公开标识符
- 类名与方法名（`util/o.b0()`、`fs90.u()` 等）—— 代码中的符号名
- 字段名（`userTable.bgControl`）—— 数据库表结构
- 系统属性名（`ro.csc.countryiso_code`）—— AOSP 公开属性

这些是**分析信息**，如同论文中引用论文标题。

---

## 五、本仓库文档的许可

文档部分采用 **MIT** 许可。

```
Copyright (c) 2026 liuchenljc

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 六、协作署名

文档撰写：`liuchenljc`
本文档由 `liuchenljc` 与 AI 助手 LC 协作完成。

---

## 七、免责

- 本仓库内容仅用于技术学习与个人设备排障研究
- 绕过厂商区域限制可能违反相关服务条款，请勿用于商业或他人设备
- 血压 / 心电数据未经医疗认证，**不能作为诊断依据**
- 使用者需自行遵守所获取软件的许可协议
