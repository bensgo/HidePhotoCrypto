# 来源与许可证检查

检查日期：2026-10-20。

| 内容 | 来源 | 发布处理 |
| --- | --- | --- |
| 本包 Swift 源码和测试 | 本次编写的通用 CryptoKit 封装及合成测试 | 采用 PolyForm Noncommercial 1.0.0，版权所有者为 YueGe |
| CryptoKit、Foundation | Apple 平台 SDK | 仅调用系统框架 API，不复制、打包或重新许可 SDK 实现 |
| Swift Testing、PackageDescription | Swift 工具链 | 测试和包清单使用，不复制其实现 |
| Python 检查脚本 | 本次编写，使用 Python 标准库 | 与本包采用相同许可证，不打包 Python |
| LICENSE 正文 | [SPDX 标准许可证全文](https://spdx.org/licenses/PolyForm-Noncommercial-1.0.0.html) | 保留完整标准正文，无自定义删改 |

`Package.swift` 没有第三方依赖，不需要为发布候选包重新许可任何第三方源码。系统框架和工具链继续受其各自条款约束，本包的 PolyForm 许可只适用于本包自身代码。

## ObscuraCrypto 参考项目

最初阅读了 [ObscuraCrypto README](https://github.com/orlio-inc/ObscuraCrypto) 以了解功能范围。该仓库使用 [GPL-3.0-or-later](https://github.com/orlio-inc/ObscuraCrypto/blob/main/LICENSE)，不能把其源码简单换一个 LICENSE 后按本次要求发布。

因此本候选目录没有复制它的源码、测试、fixtures、README 或 Git 历史，也没有添加该项目作为依赖。不声称本包具备其文件格式兼容性。上一版含 GPL 代码的仓库属于另一个产物，不在本次待发布文件范围中。

本次检查是代码与依赖清单检查，不构成第三方授予额外授权的证明。用户已指定署名为 YueGe；用户已确认创建全新公开仓库及推送。
