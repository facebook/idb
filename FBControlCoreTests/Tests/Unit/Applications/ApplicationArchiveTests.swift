/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency @testable import FBControlCore
import XCTest

/// Coverage for getting from a source of an application to a bundle on disk.
final class ApplicationArchiveTests: XCTestCase {

  private var logger: ControlCoreLoggerDouble!
  private var tempDirectory: String!
  private var scratchRoot: URL!

  override func setUp() {
    super.setUp()
    logger = ControlCoreLoggerDouble()
    tempDirectory = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(
      atPath: tempDirectory, withIntermediateDirectories: true)
    scratchRoot = URL(fileURLWithPath: path("scratch"))
  }

  override func tearDown() {
    StubURLProtocol.behaviour = .none
    try? FileManager.default.removeItem(atPath: tempDirectory)
    super.tearDown()
  }

  // MARK: - Fixtures

  private static var stubbedURL: URL {
    // swiftlint:disable:next force_unwrapping
    // patternlint-disable-next-line use-meta-url-wrapper-for-url
    return URL(string: "https://example.invalid/app.ipa")!
  }

  private func path(_ relative: String) -> String {
    (tempDirectory as NSString).appendingPathComponent(relative)
  }

  /// Everything the resolver unpacks lands under `scratchRoot`, so its contents
  /// after the call are what was left behind.
  private var temporaryDirectory: TemporaryDirectory {
    TemporaryDirectory(rootDirectory: scratchRoot, logger: logger)
  }

  private var leftBehind: [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: scratchRoot.path)) ?? []
  }

  /// Writes a loadable flat app bundle, with a real Mach-O as its executable
  /// because reading a bundle parses the header.
  @discardableResult
  private func makeAppBundle(_ relative: String, identifier: String) throws -> String {
    let bundlePath = path(relative)
    try FileManager.default.createDirectory(
      atPath: bundlePath, withIntermediateDirectories: true)
    let name = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
    try FileManager.default.copyItem(
      atPath: "/bin/ls", toPath: (bundlePath as NSString).appendingPathComponent(name))
    let info: [String: Any] = [
      "CFBundleIdentifier": identifier, "CFBundleExecutable": name, "CFBundleName": name,
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: URL(fileURLWithPath: (bundlePath as NSString).appendingPathComponent("Info.plist")))
    return bundlePath
  }

  private func makeGzippedTar(of root: String) throws -> Data {
    let data = try FBArchiveOperations.createGzippedTarData(
      forPath: root, queue: DispatchQueue.global(qos: .default), logger: logger
    ).`await`()
    return data as Data
  }

  /// A gzipped tar laid out like an `.ipa`, as raw bytes.
  private func makePayloadArchive() throws -> Data {
    let root = path("staging-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      atPath: (root as NSString).appendingPathComponent("Payload"),
      withIntermediateDirectories: true)
    let app = try makeAppBundle("Sample.app", identifier: "com.example.sample")
    try FileManager.default.moveItem(
      atPath: app, toPath: (root as NSString).appendingPathComponent("Payload/Sample.app"))
    return try makeGzippedTar(of: root)
  }

  private func makeArchiveFile() throws -> String {
    let archive = path("app-\(UUID().uuidString).ipa")
    try makePayloadArchive().write(to: URL(fileURLWithPath: archive))
    return archive
  }

  /// Resolves and returns the bundle's identity plus every progress event seen.
  private func resolve(
    _ source: InstallSource,
    downloadConfiguration: URLSessionConfiguration = .default
  ) async throws -> (identifier: String, path: String, events: [InstallProgressEvent]) {
    let collected = EventCollector()
    let result = try await ApplicationArchive.withResolvedBundle(
      from: source,
      downloadConfiguration: downloadConfiguration,
      temporaryDirectory: temporaryDirectory,
      logger: logger,
      onProgress: collected.append
    ) { bundle in
      (bundle.identifier, bundle.path)
    }
    return (result.0, result.1, collected.events)
  }

  private func resolveOverStubbedNetwork() async throws -> (identifier: String, path: String, events: [InstallProgressEvent]) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return try await resolve(.remoteURL(Self.stubbedURL), downloadConfiguration: configuration)
  }

  private func assertResolveThrows(
    _ source: @autoclosure () throws -> InstallSource,
    overStubbedNetwork: Bool = false,
    _ inspect: (Error) -> Void
  ) async throws {
    let source = try source()
    do {
      if overStubbedNetwork {
        _ = try await resolveOverStubbedNetwork()
      } else {
        _ = try await resolve(source)
      }
      XCTFail("Expected the resolution to fail")
    } catch {
      inspect(error)
    }
  }

  // MARK: - Local sources

  func testResolve_WhenGivenAnAppBundle_SkipsExtractionEntirely() async throws {
    let app = try makeAppBundle("Sample.app", identifier: "com.example.sample")

    let (identifier, resolvedPath, events) = try await resolve(.localPath(app))

    XCTAssertEqual(identifier, "com.example.sample")
    XCTAssertEqual(resolvedPath, app, "The bundle is used where it is, not copied")
    XCTAssertEqual(events.count, 0, "Nothing was downloaded and nothing was unpacked")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: scratchRoot.path), "No temporary directory was made")
  }

  func testResolve_WhenGivenAnArchiveFile_ExtractsAndFindsTheBundle() async throws {
    let archive = try makeArchiveFile()

    let (identifier, _, events) = try await resolve(.localPath(archive))

    XCTAssertEqual(identifier, "com.example.sample")
    XCTAssertEqual(events.map(\.stage), [.extract, .extract])
    XCTAssertEqual(events.map(\.phase), [.started, .completed])
  }

  func testResolve_WhenGivenAProcessInput_ExtractsAndFindsTheBundle() async throws {
    let input = FBProcessInput<NSData>(from: try makePayloadArchive())
      .retyped(FBProcessInput<AnyObject>.self)

    let (identifier, _, events) = try await resolve(.processInput(input))

    XCTAssertEqual(identifier, "com.example.sample")
    XCTAssertEqual(events.map(\.stage), [.extract, .extract])
    XCTAssertEqual(events.map(\.phase), [.started, .completed])
  }

  // MARK: - Remote sources

  func testResolve_WhenGivenAURL_ReportsDownloadAndExtractProgress() async throws {
    let archive = try makePayloadArchive()
    StubURLProtocol.behaviour = .respond(statusCode: 200, body: archive)

    let (identifier, _, events) = try await resolveOverStubbedNetwork()

    XCTAssertEqual(identifier, "com.example.sample")
    guard case .downloadStarted(_, let url)? = events.first else {
      XCTFail("Expected the download to open, got: \(events)")
      return
    }
    XCTAssertEqual(url, Self.stubbedURL)
    let completion = events.compactMap { event -> Int64? in
      guard case .downloadCompleted(_, let totalBytes) = event else { return nil }
      return totalBytes
    }
    XCTAssertEqual(completion, [Int64(archive.count)], "The download reports every byte it received")
  }

  /// The two stages are reported as nested rather than sequential: the extract
  /// stage opens before the download closes, so a renderer has both on screen at
  /// once and each stage times against its own start.
  func testResolve_WhenGivenAURL_ReportsTheStagesAsNested() async throws {
    StubURLProtocol.behaviour = .respond(statusCode: 200, body: try makePayloadArchive())

    let (_, _, events) = try await resolveOverStubbedNetwork()

    let ordering = events.map { "\($0.stage.rawValue).\($0.phase.rawValue)" }
    XCTAssertEqual(
      ordering.filter { $0.hasSuffix(".started") || $0.hasSuffix(".completed") },
      ["download.started", "extract.started", "download.completed", "extract.completed"],
      "Got: \(ordering)")
  }

  func testResolve_WhenTheServerRejectsTheRequest_FailsWithTheHTTPStatus() async throws {
    StubURLProtocol.behaviour = .respond(statusCode: 404, body: Data("nope".utf8))

    try await assertResolveThrows(.remoteURL(Self.stubbedURL), overStubbedNetwork: true) { error in
      guard case .httpStatus(_, let statusCode)? = error as? InstallError else {
        XCTFail("Expected an HTTP status failure, got: \(error)")
        return
      }
      XCTAssertEqual(statusCode, 404)
    }
    XCTAssertEqual(leftBehind, [], "A failed download leaves nothing behind")
  }

  /// The extractor sees a truncated transfer as a short archive; the transfer's
  /// own failure is what reaches the caller.
  func testResolve_WhenTheTransferFailsMidStream_FailsWithTheTransferError() async throws {
    let archive = try makePayloadArchive()
    StubURLProtocol.behaviour = .truncate(
      statusCode: 200, body: archive, bytesBeforeFailure: archive.count / 2)

    try await assertResolveThrows(.remoteURL(Self.stubbedURL), overStubbedNetwork: true) { error in
      guard case .transferFailed? = error as? InstallError else {
        XCTFail("Expected a transfer failure, got: \(error)")
        return
      }
    }
  }

  // MARK: - Temporary directory

  func testResolve_WhenDone_RemovesWhatItUnpacked() async throws {
    let archive = try makeArchiveFile()
    let before = leftBehind

    _ = try await ApplicationArchive.withResolvedBundle(
      from: .localPath(archive), temporaryDirectory: temporaryDirectory, logger: logger
    ) { bundle in
      XCTAssertTrue(
        URL(fileURLWithPath: bundle.path).resolvingSymlinksInPath().path
          .hasPrefix(scratchRoot.resolvingSymlinksInPath().path),
        "Unpacked under the given directory")
      XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.path), "Present while in use")
    }

    XCTAssertEqual(before, [])
    XCTAssertEqual(leftBehind, [], "Removed once the caller is done")
  }

  func testResolve_WhenTheCallerThrows_RemovesWhatItUnpacked() async throws {
    struct CallerFailure: Error {}
    let archive = try makeArchiveFile()

    do {
      _ = try await ApplicationArchive.withResolvedBundle(
        from: .localPath(archive), temporaryDirectory: temporaryDirectory, logger: logger
      ) { _ in
        throw CallerFailure()
      }
      XCTFail("Expected the caller's failure to propagate")
    } catch {
      XCTAssertTrue(error is CallerFailure, "Got: \(error)")
    }
    XCTAssertEqual(leftBehind, [])
  }

  // MARK: - Failures

  func testResolve_WhenTheArchiveHoldsNoApp_Fails() async throws {
    let root = path("empty-staging")
    try FileManager.default.createDirectory(
      atPath: (root as NSString).appendingPathComponent("Payload"),
      withIntermediateDirectories: true)
    try "not an app".write(
      toFile: (root as NSString).appendingPathComponent("Payload/readme.txt"),
      atomically: true, encoding: .utf8)
    let archive = path("empty.ipa")
    try makeGzippedTar(of: root).write(to: URL(fileURLWithPath: archive))

    try await assertResolveThrows(.localPath(archive)) { error in
      guard case .noInstallableBundle(_, let underlying)? = error as? InstallError,
        case .noApplicationInIPA? = underlying as? BundleDescriptorError
      else {
        XCTFail("Expected no application to be found, got: \(error)")
        return
      }
    }
    XCTAssertEqual(leftBehind, [])
  }

  func testResolve_WhenTheArchiveHoldsTwoApps_FailsRatherThanPicking() async throws {
    let root = path("two-app-staging")
    let payload = (root as NSString).appendingPathComponent("Payload")
    try FileManager.default.createDirectory(atPath: payload, withIntermediateDirectories: true)
    for name in ["First", "Second"] {
      let app = try makeAppBundle("\(name).app", identifier: "com.example.\(name.lowercased())")
      try FileManager.default.moveItem(
        atPath: app, toPath: (payload as NSString).appendingPathComponent("\(name).app"))
    }
    let archive = path("two.ipa")
    try makeGzippedTar(of: root).write(to: URL(fileURLWithPath: archive))

    try await assertResolveThrows(.localPath(archive)) { error in
      guard case .noInstallableBundle(_, let underlying)? = error as? InstallError,
        case .multipleApplicationsInIPA(let count, _)? = underlying as? BundleDescriptorError
      else {
        XCTFail("Expected an ambiguous archive to be rejected, got: \(error)")
        return
      }
      XCTAssertEqual(count, 2)
    }
  }

  func testResolve_WhenTheArchiveIsCorrupt_FailsAsAnExtractionFailure() async throws {
    let archive = path("corrupt.ipa")
    try Data("not an archive".utf8).write(to: URL(fileURLWithPath: archive))

    try await assertResolveThrows(.localPath(archive)) { error in
      guard case .extractionFailed(let underlying)? = error as? InstallError else {
        XCTFail("Expected an extraction failure, got: \(error)")
        return
      }
      XCTAssertTrue(
        (underlying as NSError).localizedDescription.contains("is not acceptable"), "Got: \(underlying)")
      XCTAssertTrue(
        (error as NSError).localizedDescription.contains("is not acceptable"),
        "The extractor's reason survives the ObjC boundary")
    }
  }
}

// MARK: - Doubles

/// Collects progress events from the pipeline's callback, which may be invoked
/// from the download's delegate queue as well as the calling task.
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
