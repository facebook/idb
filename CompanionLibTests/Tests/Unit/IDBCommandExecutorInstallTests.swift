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
  func aStreamedFrameworkOutlivesItsStaging() async throws {
    let harness = try MacInstallHarness()
    let framework = try harness.makeBundle(named: "Sample", extension: "framework", identifier: "com.example.sample")

    let artifact = try await harness.executor.install_framework_stream(try harness.gzippedTar(of: framework))

    let type = try FileManager.default.attributesOfItem(atPath: artifact.path.path)[.type] as? FileAttributeType
    #expect(type == .typeDirectory)
    #expect(FileManager.default.fileExists(atPath: artifact.path.appendingPathComponent("Info.plist").path))
  }

  @Test
  func aFrameworkAtALocalPath() async throws {
    let harness = try MacInstallHarness()
    let framework = try harness.makeBundle(named: "Sample", extension: "framework", identifier: "com.example.sample")

    // BUG: the framework's own path is listed as if it were a directory holding one framework, so its executable and Info.plist are two candidates.
    await #expect {
      _ = try await harness.executor.install_framework_file_path(framework.path)
    } throws: { error in
      error.localizedDescription.hasPrefix("Expected one top level file, found 2")
    }
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
