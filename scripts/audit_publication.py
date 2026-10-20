#!/usr/bin/env python3
# Copyright (c) 2026 YueGe
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# 仅限非商业使用；商业使用须获得版权所有者书面授权。详见 LICENSE。
"""本地只读发布检查，不创建仓库、不上传文件。"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--release", action="store_true", help="署名未确认时返回失败")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
allowed = {
    ".gitignore", "LICENSE", "Package.swift", "README.md",
    "Sources/HidePhotoCrypto/Encryption.swift",
    "Sources/HidePhotoCrypto/FileEncryption.swift",
    "Tests/HidePhotoCryptoTests/EncryptionTests.swift",
    "docs/FORMAT.md", "docs/DEPENDENCIES.md", "docs/RELEASE_REVIEW.md",
    "scripts/audit_publication.py",
}
files = set()
errors = []
for path in root.rglob("*"):
    relative = path.relative_to(root)
    if relative.parts[0] in {".build", ".swiftpm", ".git"}:
        continue
    if path.is_symlink():
        errors.append(f"符号链接不允许发布：{relative}")
    if path.is_file():
        files.add(relative.as_posix())
if files != allowed:
    errors.append(f"白名单不一致：多余={sorted(files - allowed)}，缺少={sorted(allowed - files)}")

secret_patterns = [
    r"AKIA[0-9A-Z]{16}", r"gh[pousr]_[A-Za-z0-9]{20,}",
    r"github_pat_[A-Za-z0-9_]{20,}", r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"AIza[0-9A-Za-z_-]{35}",
]
swift_files = []
for name in sorted(files & allowed):
    path = root / name
    text = path.read_text(encoding="utf-8")
    if any(re.search(pattern, text) for pattern in secret_patterns):
        errors.append(f"发现疑似凭据：{name}")
    if name.endswith(".swift"):
        swift_files.append(name)
        top = "\n".join(text.splitlines()[:6])
        if "Copyright (c) 2026 YueGe" not in top or "SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0" not in top:
            errors.append(f"缺少版权或许可证声明：{name}")
        imports = set(re.findall(r"^import (\w+)", text, re.MULTILINE))
        if imports - {"CryptoKit", "Foundation", "Testing", "PackageDescription", "HidePhotoCrypto"}:
            errors.append(f"存在未批准导入：{name}")
        if re.search(r"ObscuraCrypto|VaultSession|FolderProtection|UserDefaults|Firebase|LocalAuthentication|URLSession", text):
            errors.append(f"发现非通用范围实现：{name}")

manifest = subprocess.run(["swift", "package", "dump-package"], cwd=root, check=True, capture_output=True, text=True)
if json.loads(manifest.stdout)["dependencies"]:
    errors.append("发现第三方依赖")
if not (root / "LICENSE").read_text().startswith("# PolyForm Noncommercial License 1.0.0"):
    errors.append("许可证类型不正确")

pending = "[待确认版权所有者]" in (root / "README.md").read_text() or "[待确认商业授权联系方式]" in (root / "README.md").read_text()
for error in errors:
    print(f"失败：{error}")
print(f"发布文件 {len(files)} 个，Swift 文件 {len(swift_files)} 个，第三方 Package 依赖 0 个。")
if pending:
    print("待确认：版权所有者与商业授权联系方式；当前不满足最终发布条件。")
if not (root / ".git").exists():
    print("未初始化 Git；没有携带 Git 历史。")
else:
    print("已存在 Git 元数据；发布前需另外核对历史及远端。")
if errors or (args.release and pending):
    sys.exit(1)
print("本地内容静态检查通过；本命令不构成发布授权。")
