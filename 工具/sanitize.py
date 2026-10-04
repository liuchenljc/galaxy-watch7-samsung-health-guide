# -*- coding: utf-8 -*-
"""
隐私脱敏：把项目里的个人信息替换为占位符。

设计要点
--------
**自噬免疫**：本脚本会扫描自己的源码，若规则表里写的是明文目标值，
跑一遍就会把自己的规则改成空操作。所以所有目标值都用**字符串拼接**
或 **Unicode 转义**构造，永不出现完整明文。

替换规则（长串优先）：
    Windows 用户名   → %USERPROFILE%
    GitHub 真实邮箱  → <GITHUB_EMAIL>
    手机 serial      → <SERIAL>
    手表蓝牙 MAC     → <WATCH_MAC>
    手机蓝牙 MAC     → <PHONE_MAC>
    Wear 节点 ID     → <DEVICE_ID>
    蓝牙名里的真名   → <OWNER_PHONE_NAME>
    私有 IP          → <LAN_IP>
    token 绝对路径   → %USERPROFILE%\\.workbuddy\\.gh_token
    token 到期日     → 泛化

**保留不动**（脱敏会破坏技术内容）：
    - GitHub 用户名 —— 仓库 owner，必须一致才能推
    - 机型（SM-L310 / 23127PN0CC / houji / fresh7blzc）
    - 包名 com.samsung.* / com.sec.android.*
    - 证书 SHA256 / 文件 MD5 指纹

用法：
    python tools/sanitize.py <目录> [--dry-run]
"""
import argparse
import os
import re
import sys

# ---- 目标值：全部拼接 / 转义构造，保证脚本自身不含明文 ----
_USER = "33" + "265"
_EMAIL_LOCAL = "1033552" + "40"
_NODE = "b195" + "c1db"
_SERIAL = "7a18" + "d30e"
_GIVEN = "刘" + "辰"          # 真名（Unicode 转义等价）
_MAC_WATCH_RE = "34:[Ee]3:[Ff][Bb]:[Aa]5:4[Cc]:26"
_MAC_PHONE_RE = "38:[Cc]6:[Bb][Dd]:51:33:[Bb]6"
_LAN_IP_RE = r"192\.168\.5\.(?:214|181|164|209|134)\b"

# 文本文件扩展名
TEXT_EXT = {
    ".md", ".py", ".sh", ".bat", ".txt", ".prop", ".json", ".yml", ".yaml",
    ".cfg", ".ini", ".xml", ".smali", ".log", ".gitignore", "",
}

# 需整行删除的敏感行
LINE_DROP = re.compile(
    r"(gh_token)\s*[/\\]|token\s*文件.*绝对路径|到期\s*2026-\d\d-\d\d.*token",
    re.I,
)

RULES = [
    # GitHub 真实邮箱（commit 署名里的）
    (re.escape(_EMAIL_LOCAL + "+liuchenljc@users.noreply.github.com"), "<GITHUB_EMAIL>"),
    (r"[\w.+-]+@users\.noreply\.github\.com", "<GITHUB_EMAIL>"),
    # token 到期日：泛化，避免暴露轮换周期
    (r"（账号 \S+，到期 2026-10-31，保留复用勿 revoke）", "（账号见仓库 owner，保留复用勿 revoke）"),
    (r"到期 2026-10-31", "有效期见创建时记录"),
    # Windows 用户名（路径）。源文件里是单反斜杠，正则需写 \\\\
    (r"C:\\Users\\" + _USER, "%USERPROFILE%"),
    (r"C:/Users/" + _USER, "%USERPROFILE%"),
    (r"\.zcode[\\/]workspace", "<WORKSPACE>"),
    # 兜底：任何漏网的
    (_USER, "<USER>"),
    # 上一条产生的占位再收敛
    (r"[\\/]Users[\\/]<USER>", "\\%USERPROFILE%"),
    # 设备标识。MAC 大小写混杂且可能粘连在标识符后（info_<DEVICE_ID>），故用宽松匹配
    (_MAC_WATCH_RE, "<WATCH_MAC>"),
    (_MAC_PHONE_RE, "<PHONE_MAC>"),
    (_NODE, "<DEVICE_ID>"),
    (_SERIAL, "<SERIAL>"),
    (_LAN_IP_RE, "<LAN_IP>"),
    # 蓝牙设备名里的真实姓名（bt_config.conf 的 Name 字段会带）
    (r"= " + _GIVEN + r"的Xiaomi 14", "= <OWNER_PHONE_NAME>"),
    (_GIVEN, "<GIVEN_NAME>"),
]

# 触发扫描的关键词（用拼接构造，本文件自己不含这些明文）
TRIGGER = re.compile("|".join(re.escape(s) for s in [
    _USER, _SERIAL, _NODE,
    "34:E3", "34:e3", "38:C6", "38:c6",
    "192.168.5.", "users.noreply", "gh_token", _GIVEN,
]))


def scrub_text(text):
    out = text
    for pat, rep in RULES:
        out = re.sub(pat, rep, out)
    # 丢弃整行，但保留结尾换行状态（splitlines 会吃掉末尾换行，须还原）
    trailing = out.endswith("\n")
    kept = [l for l in out.splitlines() if not LINE_DROP.search(l)]
    out = "\n".join(kept)
    if trailing:
        out += "\n"
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    changed, scanned = [], 0

    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in (".git", "__pycache__")]
        for fn in files:
            if os.path.splitext(fn)[1].lower() not in TEXT_EXT and not fn.startswith("."):
                continue
            p = os.path.join(dirpath, fn)
            try:
                with open(p, encoding="utf-8") as f:
                    src = f.read()
            except (UnicodeDecodeError, OSError):
                continue
            scanned += 1
            if not TRIGGER.search(src):
                continue
            new = scrub_text(src)
            rel = os.path.relpath(p, root)
            if new == src:
                continue
            changed.append(rel)
            if args.dry_run:
                n = sum(1 for a, b in zip(src.splitlines(), new.splitlines()) if a != b)
                print(f"  [dry] {rel}  (~{n} 行受影响)")
            else:
                with open(p, "w", encoding="utf-8", newline="\n") as f:
                    f.write(new)
                print(f"  ✅ {rel}")

    print(f"\n扫描 {scanned} 个文本文件，需脱敏 {len(changed)} 个")
    for c in changed:
        print(f"   {c}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
