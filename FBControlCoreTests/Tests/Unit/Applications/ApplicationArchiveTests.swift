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

  private func makeGzippedTar(of root: String) async throws -> Data {
    try await FBArchiveOperations.createGzippedTarData(forPath: root, logger: logger)
  }

  /// A gzipped tar laid out like an `.ipa`, as raw bytes.
  private func makePayloadArchive() async throws -> Data {
    let root = path("staging-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      atPath: (root as NSString).appendingPathComponent("Payload"),
      withIntermediateDirectories: true)
    let app = try makeAppBundle("Sample.app", identifier: "com.example.sample")
    try FileManager.default.moveItem(
      atPath: app, toPath: (root as NSString).appendingPathComponent("Payload/Sample.app"))
    return try await makeGzippedTar(of: root)
  }

  private func makeArchiveFile() async throws -> String {
    let archive = path("app-\(UUID().uuidString).ipa")
    try await makePayloadArchive().write(to: URL(fileURLWithPath: archive))
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
    let archive = try await makeArchiveFile()

    let (identifier, _, events) = try await resolve(.localPath(archive))

    XCTAssertEqual(identifier, "com.example.sample")
    XCTAssertEqual(events.map(\.stage), [.extract, .extract])
    XCTAssertEqual(events.map(\.phase), [.started, .completed])
  }

  func testResolve_WhenGivenAProcessInput_ExtractsAndFindsTheBundle() async throws {
    let payload = try await makePayloadArchive()
    let input = FBProcessInput<NSData>(from: payload)
      .retyped(FBProcessInput<AnyObject>.self)

    let (identifier, _, events) = try await resolve(.processInput(input))

    XCTAssertEqual(identifier, "com.example.sample")
    XCTAssertEqual(events.map(\.stage), [.extract, .extract])
    XCTAssertEqual(events.map(\.phase), [.started, .completed])
  }

  private func zipStream(_ zip: Data) -> InstallSource {
    .zipStream(FBProcessInput<NSData>(from: zip).retyped(FBProcessInput<AnyObject>.self))
  }

  func testResolve_WhenGivenAZipStream_RestoresWhatOnlyItsCentralDirectoryRecords() async throws {
    let zip = try makeZippedPayloadWithSymlink()

    let (identifier, linkType, executablePermissions) = try await ApplicationArchive.withResolvedBundle(
      from: zipStream(zip), temporaryDirectory: temporaryDirectory, logger: logger
    ) { bundle in
      let manager = FileManager.default
      return (
        bundle.identifier,
        try manager.attributesOfItem(atPath: (bundle.path as NSString).appendingPathComponent("Link.plist"))[.type] as? FileAttributeType,
        try manager.attributesOfItem(atPath: (bundle.path as NSString).appendingPathComponent("Sample"))[.posixPermissions] as? Int
      )
    }

    XCTAssertEqual(identifier, "com.example.sample")
    XCTAssertEqual(linkType, .typeSymbolicLink)
    XCTAssertEqual(executablePermissions, 0o755)
  }

  /// A reader of the stream cannot handle a stored entry with its size after it.
  func testResolve_WhenAZipStreamCannotBeExtractedAsItArrives_ExtractsTheSpooledZip() async throws {
    let zip = try makeZippedPayloadWithSymlink(firstEntryStoredWithSizeAfter: true)

    let (identifier, _, events) = try await resolve(zipStream(zip))

    XCTAssertEqual(identifier, "com.example.sample")
    XCTAssertEqual(events.map(\.phase), [.started, .completed], "The fallback is part of the one extract stage")
    XCTAssertEqual(leftBehind, [], "The spooled zip is removed with what it unpacked")
  }

  // MARK: - Remote sources

  func testResolve_WhenGivenAURL_ReportsDownloadAndExtractProgress() async throws {
    let archive = try await makePayloadArchive()
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
    let payload = try await makePayloadArchive()
    StubURLProtocol.behaviour = .respond(statusCode: 200, body: payload)

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
    let archive = try await makePayloadArchive()
    StubURLProtocol.behaviour = .truncate(
      statusCode: 200, body: archive, bytesBeforeFailure: archive.count / 2)

    try await assertResolveThrows(.remoteURL(Self.stubbedURL), overStubbedNetwork: true) { error in
      guard case .transferFailed? = error as? InstallError else {
        XCTFail("Expected a transfer failure, got: \(error)")
        return
      }
    }
  }

  /// A zip records symlinks only in its central directory, at the end of the
  /// archive, which an extractor reading the transfer as it arrives never sees.
  func testResolve_WhenGivenAZipURL_RestoresItsSymlinks() async throws {
    StubURLProtocol.behaviour = .respond(statusCode: 200, body: try makeZippedPayloadWithSymlink())
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]

    let linkType = try await ApplicationArchive.withResolvedBundle(
      from: .remoteURL(Self.stubbedURL),
      downloadConfiguration: configuration,
      temporaryDirectory: temporaryDirectory,
      logger: logger
    ) { bundle in
      try FileManager.default.attributesOfItem(
        atPath: (bundle.path as NSString).appendingPathComponent("Link.plist"))[.type] as? FileAttributeType
    }

    XCTAssertEqual(linkType, .typeSymbolicLink)
  }

  func testResolve_WhenGivenAZstdZipURL_RestoresItsSymlinks() async throws {
    StubURLProtocol.behaviour = .respond(statusCode: 200, body: ArchiveFormat.zstdZipMarker + Self.zstd(try makeZippedPayloadWithSymlink()))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]

    let linkType = try await ApplicationArchive.withResolvedBundle(
      from: .remoteURL(Self.stubbedURL),
      downloadConfiguration: configuration,
      temporaryDirectory: temporaryDirectory,
      logger: logger
    ) { bundle in
      try FileManager.default.attributesOfItem(
        atPath: (bundle.path as NSString).appendingPathComponent("Link.plist"))[.type] as? FileAttributeType
    }

    // BUG: the download is sniffed on fewer bytes than the zstd zip marker, so it is read as a zstd tar and its zip reaches bsdtar on stdin; flipped in the following commit.
    XCTAssertEqual(linkType, .typeRegular)
  }

  /// `data` in a zstd frame of uncompressed blocks, as the tests cannot rely on a zstd compressor being installed.
  private static func zstd(_ data: Data) -> Data {
    var frame = Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x38])
    var offset = data.startIndex
    repeat {
      let size = min(data.endIndex - offset, 1 << 17)
      let last = offset + size == data.endIndex
      let header = UInt32(size) << 3 | (last ? 1 : 0)
      frame.append(contentsOf: [UInt8(header & 0xFF), UInt8(header >> 8 & 0xFF), UInt8(header >> 16)])
      frame.append(data[offset..<offset + size])
      offset += size
    } while offset < data.endIndex
    return frame
  }

  func testResolve_WhenAZipTransferFailsMidStream_FailsWithTheTransferError() async throws {
    let zip = try makeZippedPayloadWithSymlink()
    StubURLProtocol.behaviour = .truncate(statusCode: 200, body: zip, bytesBeforeFailure: zip.count / 2)

    try await assertResolveThrows(.remoteURL(Self.stubbedURL), overStubbedNetwork: true) { error in
      guard case .transferFailed? = error as? InstallError else {
        XCTFail("Expected a transfer failure, got: \(error)")
        return
      }
    }
  }

  /// A zip laid out like an `.ipa` whose app holds `Link.plist -> Info.plist`. With `firstEntryStoredWithSizeAfter`,
  /// its entries are stored and the first one's local header claims its size follows it, which only its central
  /// directory contradicts.
  private func makeZippedPayloadWithSymlink(identifier: String = "com.example.sample", firstEntryStoredWithSizeAfter: Bool = false) throws -> Data {
    let root = path("zip-staging-\(UUID().uuidString)")
    let payload = (root as NSString).appendingPathComponent("Payload")
    try FileManager.default.createDirectory(atPath: payload, withIntermediateDirectories: true)
    let app = try makeAppBundle("Sample.app", identifier: identifier)
    let staged = (payload as NSString).appendingPathComponent("Sample.app")
    try FileManager.default.moveItem(atPath: app, toPath: staged)
    try FileManager.default.createSymbolicLink(
      atPath: (staged as NSString).appendingPathComponent("Link.plist"),
      withDestinationPath: "Info.plist")
    let archive = path("symlink-\(UUID().uuidString).ipa")
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = URL(fileURLWithPath: root)
    zip.arguments = [firstEntryStoredWithSizeAfter ? "-qry0" : "-qry", archive, "Payload"]
    try zip.run()
    zip.waitUntilExit()
    XCTAssertEqual(zip.terminationStatus, 0)
    var data = try Data(contentsOf: URL(fileURLWithPath: archive))
    if firstEntryStoredWithSizeAfter {
      // Bit 3 of the general purpose flags, at offset 6 of the local header.
      data[6] |= 0x08
    }
    return data
  }

  // MARK: - Temporary directory

  func testResolve_WhenDone_RemovesWhatItUnpacked() async throws {
    let archive = try await makeArchiveFile()
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
    let archive = try await makeArchiveFile()

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
    try await makeGzippedTar(of: root).write(to: URL(fileURLWithPath: archive))

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
    try await makeGzippedTar(of: root).write(to: URL(fileURLWithPath: archive))

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
