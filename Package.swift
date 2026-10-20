// swift-tools-version: 6.0
// Copyright (c) 2026 YueGe
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// 仅限非商业使用；商业使用须获得版权所有者书面授权。详见 LICENSE。
import PackageDescription

let package = Package(
    name: "HidePhotoCrypto",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "HidePhotoCrypto", targets: ["HidePhotoCrypto"])],
    targets: [
        .target(name: "HidePhotoCrypto"),
        .testTarget(name: "HidePhotoCryptoTests", dependencies: ["HidePhotoCrypto"]),
    ]
)
