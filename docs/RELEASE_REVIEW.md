# 发布检查说明

本地候选目录独立于上一版 Git 仓库，未复制 `.git`，不携带原项目历史。

允许发布的文件只限：根目录 Package.swift、README.md、LICENSE、.gitignore，两个通用源文件，一个合成测试文件，三个说明文档和发布检查脚本。构建输出不在发布范围。

## 已获用户确认

版权声明已按用户要求统一为 `Copyright (c) 2026 YueGe`，商业授权通过 GitHub Issues 联系，不包含个人真实姓名、地址或私人邮箱。

1. 新独立公开 GitHub 仓库：`bensgo/HidePhotoCrypto`。
2. 用户已在查看本地候选包及测试结果后，明确确认创建公开仓库和推送。

在上述确认前不执行 `gh repo create`、不配置公开远端、不执行 `git push`。确认后仅在本目录初始化全新 Git 仓库并创建首个提交，不从现有仓库 clone、复制 `.git` 或迁移 commit。

## 发布范围

只提交本目录白名单文件，不复制任何已有 Git 仓库元数据、业务源码或历史提交。Git 提交作者与提交者统一使用 YueGe 及 GitHub 的公开 noreply 地址，不使用私人邮箱。

## 检查命令

```sh
python3 scripts/audit_publication.py
swift package dump-package
swift build -c release
swift test
xcodebuild -scheme HidePhotoCrypto -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/hide-photo-public-ios CODE_SIGNING_ALLOWED=NO build
```

脚本执行文件白名单、源码版权及许可证头、导入模块、依赖和常见凭据模式检查。署名与联系方式未补齐时会明确标记为待发布阻塞项；`--release` 模式会返回失败。自动检查无法证明不存在所有形式的敏感信息，发布前仍需人工查看完整文件清单与 diff。

## 本地验证结果（2026-10-20）

- 静态检查：11 个发布文件、4 个 Swift 文件、零第三方 Package 依赖；白名单、常见凭据和许可证头检查通过。
- `swift package dump-package` 和 macOS Release 构建通过。
- `swift test`：7 组测试通过，包含 16 个参数化及独立用例；大文件使用 32 MiB 加 3 字节合成数据。
- iOS 通用设备目标编译通过（Xcode 26.6），未启动模拟器。
- 原 App 工作树无未提交改动。发布前候选目录未初始化 Git；本次仅为通用模块创建全新根提交及独立远端。
