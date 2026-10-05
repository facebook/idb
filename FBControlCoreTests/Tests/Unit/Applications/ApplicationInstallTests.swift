/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency @testable import FBControlCore
import XCTest

/// Coverage for installing from any source, on top of resolving one to a bundle.
final class ApplicationInstallTests: XCTestCase {

  private var logger: ControlCoreLoggerDouble!
  private var target: RecordingApplicationCommands!
  private var tempDirectory: String!

  override func setUp() {
    super.setUp()
    logger = ControlCoreLoggerDouble()
    target = RecordingApplicationCommands()
    tempDirectory = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(
      atPath: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: tempDirectory)
    super.tearDown()
  }

  // MARK: - Fixtures

  private func path(_ relative: String) -> String {
    (tempDirectory as NSString).appendingPathComponent(relative)
  }

  private var temporaryDirectory: TemporaryDirectory {
    TemporaryDirectory(rootDirectory: URL(fileURLWithPath: path("scratch")), logger: logger)
  }

  @discardableResult
  private func makeAppBundle(_ relative: String, identifier: String) throws -> String {
    let bundlePath = path(relative)
    try FileManager.default.createDirectory(
      atPath: bundlePath, withIntermediateDirectories: true)
    let executable = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
    try FileManager.default.copyItem(
      atPath: "/bin/ls", toPath: (bundlePath as NSString).appendingPathComponent(executable))
    let info: [String: Any] = [
      "CFBundleIdentifier": identifier, "CFBundleExecutable": executable, "CFBundleName": executable,
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: URL(fileURLWithPath: (bundlePath as NSString).appendingPathComponent("Info.plist")))
    return bundlePath
  }

  private func makeArchiveFile() async throws -> String {
    let root = path("staging")
    try FileManager.default.createDirectory(
      atPath: (root as NSString).appendingPathComponent("Payload"), withIntermediateDirectories: true)
    try makeAppBundle("staging/Payload/Sample.app", identifier: "com.example.sample")
    let data = try await FBArchiveOperations.createGzippedTarData(forPath: root, logger: logger)
    let archive = path("app.ipa")
    try data.write(to: URL(fileURLWithPath: archive))
    return archive
  }

  func testInstall_WhenGivenABundle_InstallsItInPlaceAndReportsOnlyTheInstallStage() async throws {
    let app = try makeAppBundle("Sample.app", identifier: "com.example.sample")
    let events = EventCollector()

    let installed = try await target.install(
      from: .localPath(app), temporaryDirectory: temporaryDirectory, logger: logger, onProgress: events.append)

    XCTAssertEqual(installed.bundle.identifier, "com.example.sample")
    XCTAssertEqual(target.installedPaths, [app])
    XCTAssertEqual(events.events.map(\.stage), [.install, .install])
  }

  func testInstall_WhenGivenAnArchive_ReportsExtractionThenInstall() async throws {
    let archive = try await makeArchiveFile()
    let events = EventCollector()

    let installed = try await target.install(
      from: .localPath(archive), temporaryDirectory: temporaryDirectory, logger: logger, onProgress: events.append)

    XCTAssertEqual(installed.bundle.identifier, "com.example.sample")
    XCTAssertEqual(
      events.events.map { "\($0.stage.rawValue).\($0.phase.rawValue)" },
      ["extract.started", "extract.completed", "install.started", "install.completed"])
    guard case .installCompleted(_, _, let bundleId)? = events.events.last else {
      XCTFail("Expected the install to complete last, got: \(events.events)")
      return
    }
    XCTAssertEqual(bundleId, "com.example.sample")
  }

  func testInstall_WhenTheTargetRefuses_ReportsNoCompletion() async throws {
    let app = try makeAppBundle("Sample.app", identifier: "com.example.sample")
    target.failure = TargetRefusal()
    let events = EventCollector()

    do {
      _ = try await target.install(
        from: .localPath(app), temporaryDirectory: temporaryDirectory, logger: logger, onProgress: events.append)
      XCTFail("Expected the install to fail")
    } catch {
      XCTAssertTrue(error is TargetRefusal, "Got: \(error)")
    }
    XCTAssertEqual(events.events.map(\.phase), [.started])
  }

  func testInstall_TimesTheInstallStageAgainstItsOwnStart() async throws {
    let archive = try await makeArchiveFile()
    target.delay = 0.1
    let events = EventCollector()

    _ = try await target.install(
      from: .localPath(archive), temporaryDirectory: temporaryDirectory, logger: logger, onProgress: events.append)

    let completed = try XCTUnwrap(events.events.last)
    XCTAssertEqual(completed.stage, .install)
    XCTAssertEqual(completed.phase, .completed)
    XCTAssertGreaterThanOrEqual(completed.elapsedMs, 100)
    XCTAssertGreaterThanOrEqual(completed.totalElapsedMs, completed.elapsedMs)
  }
}

// MARK: - Doubles

private struct TargetRefusal: Error {}

/// An `ApplicationCommands` that records what it was asked to install rather than
/// touching a simulator or a device.
// SAFETY: `failure` and `delay` are set before the call under test, and
// `installedPaths` is appended to by that one call and read once it has returned.
// patternlint-disable-next-line unchecked-sendable
private final class RecordingApplicationCommands: ApplicationCommands, @unchecked Sendable {

  private(set) var installedPaths: [String] = []
  var failure: Error?
  var delay: TimeInterval = 0

  func install(atPath path: String) async throws -> InstalledApplication {
    if delay > 0 {
      try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
    if let failure {
      throw failure
    }
    installedPaths.append(path)
    return InstalledApplication(bundle: try BundleDescriptor.bundle(fromPath: path), installType: .user, dataContainer: nil)
  }

  func uninstall(bundleID: String) async throws {}

  func kill(bundleID: String) async throws {}

  func installed() async throws -> [InstalledApplication] { [] }

  func installed(bundleID: String) async throws -> InstalledApplication {
    throw Unimplemented()
  }

  func running() async throws -> [String: pid_t] { [:] }

  func processID(forBundleID bundleID: String) async throws -> pid_t {
    throw Unimplemented()
  }

  func launch(_ configuration: ApplicationLaunchConfiguration) async throws -> LaunchedApplication {
    throw Unimplemented()
  }

  private struct Unimplemented: Error {}
}

// SAFETY: every access holds `lock`.
// patternlint-disable-next-line unchecked-sendable
private final class EventCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [InstallProgressEvent] = []

  var events: [InstallProgressEvent] {
    lock.withLock { storage }
  }

  @Sendable func append(_ event: InstallProgressEvent) {
    lock.withLock { storage.append(event) }
  }
}
