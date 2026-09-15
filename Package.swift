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
    .macOS(.v15)
  ],
  products: [
    .executable(name: "idb-repl", targets: ["idb-repl"])
  ],
  dependencies: [
    .package(url: "https://github.com/grpc/grpc-swift-2.git", exact: "2.4.3"),
    .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", exact: "2.9.2"),
    .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", exact: "2.4.1"),
    .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
    // Transitive dependencies of the gRPC packages, pinned to the versions the
    // internal build imports so the two dependency graphs stay identical
    // (dependency_parity.bzl checks this).
    .package(url: "https://github.com/apple/swift-nio.git", exact: "2.101.3"),
    .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.37.2"),
    .package(url: "https://github.com/apple/swift-nio-http2.git", exact: "1.45.0"),
    .package(url: "https://github.com/apple/swift-nio-extras.git", exact: "1.34.3"),
    .package(url: "https://github.com/apple/swift-log.git", exact: "1.14.0"),
    .package(url: "https://github.com/apple/swift-collections.git", exact: "1.6.0"),
    .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.19.4"),
    .package(url: "https://github.com/apple/swift-asn1.git", exact: "1.7.1"),
    .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
    .package(url: "https://github.com/apple/swift-async-algorithms.git", exact: "1.1.5"),
    .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", exact: "2.12.0"),
    .package(url: "https://github.com/apple/swift-atomics.git", exact: "1.3.1"),
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
        .product(name: "GRPCCore", package: "grpc-swift-2"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      path: "IDBGRPCSwift",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    // The shared REPL Swift compiler (source generation + swiftc), linked by
    // idb-repl to compile injected code client-side. Pure Swift + Foundation.
    .target(
      name: "ReplCompiler",
      path: "REPL/Compiler"
    ),
    .executableTarget(
      name: "idb-repl",
      dependencies: [
        "CompanionUtilities",
        "CompanionDiscovery",
        "IDBGRPCSwift",
        "ReplCompiler",
        .product(name: "GRPCCore", package: "grpc-swift-2"),
        .product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
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
