/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import Foundation
import Testing

@Suite
struct IDBCommandExecutorInstallTests {

  @Test
  func aStreamedDylibIsStoredUnderItsName() async throws {
    let harness = try MacInstallHarness()
    let dylib = try harness.makeFile(named: "libSample.dylib")

    let artifact = try await harness.executor.install_dylib_stream(try harness.gzipped(dylib), name: "libSample.dylib")

    #expect(artifact.name == "libSample.dylib")
    #expect(FileManager.default.contentsEqual(atPath: artifact.path.path, andPath: dylib.path))
  }

  @Test
  func aStreamedFrameworkIsStoredUnderItsIdentifier() async throws {
    let harness = try MacInstallHarness()
    let framework = try harness.makeBundle(named: "Sample", extension: "framework", identifier: "com.example.sample")

    let artifact = try await harness.executor.install_framework_stream(try harness.gzippedTar(of: framework))

    #expect(artifact.name == "com.example.sample")
    #expect(artifact.path.lastPathComponent == "Sample.framework")
  }

  @Test
  func aStreamedAppIsInstalledUnderItsIdentifier() async throws {
    let harness = try MacInstallHarness()
    let app = try harness.makeBundle(named: "Sample", extension: "app", identifier: "com.example.sample")

    let artifact = try await harness.executor.install_app_stream(try harness.gzippedTar(of: app), compression: .GZIP, make_debuggable: false, override_modification_time: false)

    #expect(artifact.name == "com.example.sample")
    #expect(harness.executor.storageManager.application.persistedBundleIDs == ["com.example.sample"])
  }
}
