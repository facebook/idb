/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBControlCore
import Foundation
import Testing
import os

@Suite
struct IDBCommandExecutorInstallTests {

  @Test
  func aStreamedDylibIsStoredUnderItsName() async throws {
    let harness = try MacInstallHarness()
    let dylib = try harness.makeFile(named: "libSample.dylib")

    let artifact = try await harness.executor.install_dylib_stream(try await harness.gzipped(dylib), name: "libSample.dylib")

    #expect(artifact.name == "libSample.dylib")
    #expect(FileManager.default.contentsEqual(atPath: artifact.path.path, andPath: dylib.path))
  }

  @Test
  func aStreamedFrameworkIsStoredUnderItsIdentifier() async throws {
    let harness = try MacInstallHarness()
    let framework = try harness.makeBundle(named: "Sample", extension: "framework", identifier: "com.example.sample")

    let artifact = try await harness.executor.install_framework_stream(try await harness.gzippedTar(of: framework))

    #expect(artifact.name == "com.example.sample")
    #expect(artifact.path.lastPathComponent == "Sample.framework")
  }

  @Test
  func aStreamedFrameworkOutlivesItsStaging() async throws {
    let harness = try MacInstallHarness()
    let framework = try harness.makeBundle(named: "Sample", extension: "framework", identifier: "com.example.sample")

    let artifact = try await harness.executor.install_framework_stream(try await harness.gzippedTar(of: framework))

    let type = try FileManager.default.attributesOfItem(atPath: artifact.path.path)[.type] as? FileAttributeType
    #expect(type == .typeDirectory)
    #expect(FileManager.default.fileExists(atPath: artifact.path.appendingPathComponent("Info.plist").path))
  }

  @Test
  func aFrameworkAtALocalPath() async throws {
    let harness = try MacInstallHarness()
    let framework = try harness.makeBundle(named: "Sample", extension: "framework", identifier: "com.example.sample")

    let artifact = try await harness.executor.install_framework_file_path(framework.path)

    #expect(artifact.name == "com.example.sample")
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: artifact.path.path) == framework.path)
  }

  @Test
  func aStreamedAppIsInstalledUnderItsIdentifier() async throws {
    let harness = try MacInstallHarness()
    let app = try harness.makeBundle(named: "Sample", extension: "app", identifier: "com.example.sample")

    let artifact = try await harness.executor.install_app_stream(try await harness.gzippedTar(of: app), compression: .GZIP, make_debuggable: false, override_modification_time: false)

    #expect(artifact.name == "com.example.sample")
    #expect(harness.executor.storageManager.application.persistedBundleIDs == ["com.example.sample"])
  }

  @Test
  func aStreamedAppIsRegisteredWhereItWasPersisted() async throws {
    let harness = try MacInstallHarness()
    let app = try harness.makeBundle(named: "Sample", extension: "app", identifier: "com.example.sample")

    let artifact = try await harness.executor.install_app_stream(try await harness.gzippedTar(of: app), compression: .GZIP, make_debuggable: false, override_modification_time: false)

    #expect(FileManager.default.fileExists(atPath: artifact.path.path))
    #expect(try await harness.target.application.installed(bundleID: "com.example.sample").bundle.path == artifact.path.path)
  }

  @Test
  func aStreamedXctestIsStoredUnderItsIdentifier() async throws {
    let harness = try MacInstallHarness()
    let xctest = try harness.makeBundle(named: "SampleTests", extension: "xctest", identifier: "com.example.sampletests")

    let artifact = try await harness.executor.install_xctest_app_stream(try await harness.gzippedTar(of: xctest), skipSigningBundles: true)

    #expect(artifact.name == "com.example.sampletests")
    #expect(try harness.executor.storageManager.xctest.testDescriptor(withID: "com.example.sampletests").url.lastPathComponent == "SampleTests.xctest")
  }

  @Test
  func anUncompressedTarStreamIsExtractedDespiteTheDeclaredGzip() async throws {
    let harness = try MacInstallHarness()
    let framework = try harness.makeBundle(named: "Sample", extension: "framework", identifier: "com.example.sample")

    let artifact = try await harness.executor.install_framework_stream(try harness.tar(of: framework))

    #expect(artifact.name == "com.example.sample")
  }

  @Test
  func aStreamedDsymIsStoredAsItsOnlyItem() async throws {
    let harness = try MacInstallHarness()
    let dsym = try harness.makeBundle(named: "Sample", extension: "dSYM", identifier: "com.example.sample")

    let artifact = try await harness.executor.install_dsym_stream(try await harness.gzippedTar(of: dsym), compression: .GZIP, linkTo: nil)

    #expect(artifact.name == "Sample.dSYM")
    #expect(artifact.path.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == harness.executor.storageManager.dsym.basePath.standardizedFileURL.path)
    #expect(FileManager.default.fileExists(atPath: artifact.path.appendingPathComponent("Info.plist").path))
  }

  @Test
  func aStreamedDsymOfSeveralItemsIsStoredAsTheirDirectory() async throws {
    let harness = try MacInstallHarness()
    let dsym = try harness.makeBundle(named: "Sample", extension: "dSYM", identifier: "com.example.sample")
    try FileManager.default.copyItem(at: dsym, to: dsym.deletingLastPathComponent().appendingPathComponent("Other.dSYM"))

    let artifact = try await harness.executor.install_dsym_stream(try await harness.gzippedTar(of: dsym), compression: .GZIP, linkTo: nil)

    let children = try FileManager.default.contentsOfDirectory(atPath: artifact.path.path).sorted()
    #expect(children == ["Other.dSYM", "Sample.dSYM"])
  }

  @Test
  func aStreamedDsymIsLinkedBesideTheAppItNames() async throws {
    let harness = try MacInstallHarness()
    let app = try harness.makeBundle(named: "Sample", extension: "app", identifier: "com.example.sample")
    let installed = try await harness.executor.install_app_stream(try await harness.gzippedTar(of: app), compression: .GZIP, make_debuggable: false, override_modification_time: false)
    let dsym = try harness.makeBundle(named: "Sample", extension: "dSYM", identifier: "com.example.sample")

    let artifact = try await harness.executor.install_dsym_stream(try await harness.gzippedTar(of: dsym), compression: .GZIP, linkTo: DsymInstallLinkToBundle(bundleID: "com.example.sample", bundleType: .app))

    let link = installed.path.deletingLastPathComponent().appendingPathComponent("Sample.dSYM")
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == artifact.path.path)
  }

  // MARK: - Progress

  private final class ProgressEvents: Sendable {
    private let events = OSAllocatedUnfairLock<[InstallProgressEvent]>(initialState: [])

    var all: [InstallProgressEvent] { events.withLock { $0 } }

    var stages: [String] { all.map { "\($0.stage.rawValue).\($0.phase.rawValue)" } }

    func append(_ event: InstallProgressEvent) {
      events.withLock { $0.append(event) }
    }
  }

  @Test
  func aStreamedFrameworkReportsItsExtractionThenItsInstall() async throws {
    let harness = try MacInstallHarness()
    let framework = try harness.makeBundle(named: "Sample", extension: "framework", identifier: "com.example.sample")
    let progress = ProgressEvents()

    let artifact = try await harness.executor.install_framework_stream(try await harness.gzippedTar(of: framework), on_progress: progress.append)

    #expect(progress.stages == ["extract.started", "extract.completed", "install.started", "install.completed"])
    guard case .installCompleted(_, let artifactPath, let name)? = progress.all.last else {
      Issue.record("Expected the install to complete last, got \(progress.all)")
      return
    }
    #expect((artifactPath as NSString).lastPathComponent == "Sample.framework")
    #expect(name == artifact.name)
  }

  @Test
  func aFrameworkAtALocalPathReportsOnlyItsInstall() async throws {
    let harness = try MacInstallHarness()
    let framework = try harness.makeBundle(named: "Sample", extension: "framework", identifier: "com.example.sample")
    let progress = ProgressEvents()

    _ = try await harness.executor.install_framework_file_path(framework.path, on_progress: progress.append)

    #expect(progress.stages == ["install.started", "install.completed"])
  }

  @Test
  func aStreamedDylibReportsItsDecompressionAsExtraction() async throws {
    let harness = try MacInstallHarness()
    let dylib = try harness.makeFile(named: "libSample.dylib")
    let progress = ProgressEvents()

    _ = try await harness.executor.install_dylib_stream(try await harness.gzipped(dylib), name: "libSample.dylib", on_progress: progress.append)

    #expect(progress.stages == ["extract.started", "extract.completed", "install.started", "install.completed"])
  }

  @Test
  func aTarPushedToDylibStorageLandsAtTheDestination() async throws {
    let harness = try MacInstallHarness()
    let dylib = try harness.makeFile(named: "libSample.dylib")

    try await harness.executor.push_file_from_tar(try await harness.gzippedTarData(of: dylib), to_path: "nested", containerType: "dylib")

    let pushed = harness.executor.storageManager.dylib.basePath.appendingPathComponent("nested/libSample.dylib")
    #expect(FileManager.default.contentsEqual(atPath: pushed.path, andPath: dylib.path))
  }
}
