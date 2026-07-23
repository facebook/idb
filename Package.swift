// swift-tools-version:6.0
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import PackageDescription

// A Swift Package Manager build for the `idb-repl` CLI. This is an ADDITIONAL,
// standalone way to build idb-repl (`swift build --product idb-repl`); it does not
// replace or affect the xcodebuild (`build.sh`) or Buck builds. It is possible
// because idb-repl and its entire dependency closure -- CompanionUtilities,
// CompanionDiscovery and the generated IDBGRPCSwift -- are pure Swift, so none of
// the Objective-C simulator/device frameworks are involved.
//
// The tools-version of 6.0 means every target builds in the Swift 6 language mode
// by default.
let package = Package(
  name: "idb",
  platforms: [
    .macOS(.v12)
  ],
  products: [
    .executable(name: "idb-repl", targets: ["idb-repl"])
  ],
  dependencies: [
    .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.19.1"),
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.50.0"),
    .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.25.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
  ],
  targets: [
    .target(
      name: "CompanionUtilities",
      path: "CompanionUtilities"
    ),
    .target(
      name: "CompanionDiscovery",
      path: "CompanionDiscovery"
    ),
    // The gRPC/protobuf types generated from proto/idb.proto (checked in under
    // IDBGRPCSwift/). Run `./build.sh generate-proto` to regenerate them.
    .target(
      name: "IDBGRPCSwift",
      dependencies: [
        .product(name: "GRPC", package: "grpc-swift"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        .product(name: "NIO", package: "swift-nio"),
        .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
      ],
      path: "IDBGRPCSwift"
    ),
    .executableTarget(
      name: "idb-repl",
      dependencies: [
        "CompanionUtilities",
        "CompanionDiscovery",
        "IDBGRPCSwift",
        .product(name: "GRPC", package: "grpc-swift"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOSSL", package: "swift-nio-ssl"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "REPL/CLI",
      // main.swift declares `@main`, so it must be parsed as a library rather
      // than as top-level script code (mirrors OTHER_SWIFT_FLAGS in the
      // xcodebuild build and -parse-as-library in the Buck build).
      swiftSettings: [
        .unsafeFlags(["-parse-as-library"])
      ],
      // Generates BuildInfo.swift (kBuildDate / kBuildTime) at build time, the
      // SwiftPM equivalent of the xcodebuild preBuildScript and Buck :BuildInfo
      // genrule. Keeps the generated file out of the shared REPL/CLI sources.
      plugins: [
        "GenerateBuildInfo"
      ]
    ),
    .plugin(
      name: "GenerateBuildInfo",
      capability: .buildTool(),
      path: "Plugins/GenerateBuildInfo"
    ),
  ]
)
