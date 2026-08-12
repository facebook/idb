/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CompanionLib
@preconcurrency import FBControlCore
import XCTest

/// Coverage for downloading an archive over HTTP and feeding it straight into
/// extraction, which is how installing from a URL is wired: the download's
/// `FBProcessInput` becomes the extracting process's stdin.
final class FBDataDownloadInputTests: XCTestCase {

  private var logger: FBControlCoreLogger!
  private var tempDirectory: String!

  override func setUp() {
    super.setUp()
    logger = DownloadTestLogger()
    tempDirectory = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(
      atPath: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    StubURLProtocol.behaviour = .none
    try? FileManager.default.removeItem(atPath: tempDirectory)
    super.tearDown()
  }

  // MARK: - Fixtures

  private static let payloadContents = "payload-contents"

  /// Real gzip bytes for a directory holding a single known file. `padding` adds
  /// incompressible bytes, so that a half-sized prefix of the result is
  /// unambiguously a truncated gzip stream rather than a plausible short one.
  private func makeArchiveData(padding: Int = 0) throws -> Data {
    let source = (tempDirectory as NSString).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(atPath: source, withIntermediateDirectories: true)
    try Self.payloadContents.write(
      toFile: (source as NSString).appendingPathComponent("payload.txt"),
      atomically: true,
      encoding: .utf8)
    if padding > 0 {
      var random = Data(count: padding)
      random.withUnsafeMutableBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        arc4random_buf(base, padding)
      }
      try random.write(
        to: URL(fileURLWithPath: (source as NSString).appendingPathComponent("padding.bin")))
    }
    let data = try FBArchiveOperations.createGzippedTarData(
      forPath: source, queue: DispatchQueue.global(qos: .default), logger: logger
    ).`await`()
    return data as Data
  }

  /// Downloads from the stubbed URL and extracts the result, exactly as the URL
  /// install path composes the two.
  private func downloadAndExtract() throws -> String {
    let destination = (tempDirectory as NSString).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      atPath: destination, withIntermediateDirectories: true)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    // swiftlint:disable:next force_unwrapping
    // patternlint-disable-next-line use-meta-url-wrapper-for-url
    let url = URL(string: "https://example.invalid/app.ipa")!
    let download = FBDataDownloadInput.dataDownload(
      withURL: url,
      configuration: configuration,
      logger: logger)
    let future = FBArchiveOperations.extractArchive(
      fromStream: download.input,
      toPath: destination,
      overrideModificationTime: false,
      logger: logger,
      compression: .GZIP)
    return try future.`await`() as String
  }

  // MARK: - Success

  func testDownload_WhenResponseIsOK_ExtractsTheDownloadedArchive() throws {
    StubURLProtocol.behaviour = .respond(statusCode: 200, body: try makeArchiveData())

    let destination = try downloadAndExtract()

    XCTAssertEqual(
      try String(
        contentsOfFile: (destination as NSString).appendingPathComponent("payload.txt"),
        encoding: .utf8),
      Self.payloadContents)
  }

  // MARK: - HTTP errors

  // BUG: the response status is never inspected, so an error page is piped into
  // the extractor as though it were the archive. The caller is told the archive
  // is malformed, and never that the server returned 404.
  func testDownload_WhenResponseIsNotFound_FeedsTheErrorPageToTheExtractor() throws {
    let errorPage = Data("<html><title>404 Not Found</title></html>".utf8)
    StubURLProtocol.behaviour = .respond(statusCode: 404, body: errorPage)

    XCTAssertThrowsError(try downloadAndExtract()) { error in
      let description = (error as NSError).localizedDescription
      XCTAssertFalse(
        description.localizedCaseInsensitiveContains("404"),
        "BUG: the HTTP status is nowhere in the failure, got: \(description)")
      XCTAssertFalse(
        description.localizedCaseInsensitiveContains("http"),
        "BUG: the failure does not mention HTTP at all, got: \(description)")
    }
  }

  // BUG: a 500 is indistinguishable from a 404 for the same reason -- neither is
  // looked at, so both surface as an unreadable archive.
  func testDownload_WhenResponseIsServerError_FeedsTheErrorPageToTheExtractor() throws {
    StubURLProtocol.behaviour = .respond(
      statusCode: 500, body: Data("internal server error".utf8))

    XCTAssertThrowsError(try downloadAndExtract()) { error in
      let description = (error as NSError).localizedDescription
      XCTAssertFalse(
        description.localizedCaseInsensitiveContains("500"),
        "BUG: the HTTP status is nowhere in the failure, got: \(description)")
    }
  }

  // BUG: worse than the cases above -- a non-200 with an empty body reaches the
  // extractor as an empty stream, which bsdtar treats as a valid empty archive
  // and exits 0. The download reports outright success, and the request is only
  // discovered to have failed further along, when no app can be found in what
  // was supposedly unpacked.
  func testDownload_WhenResponseIsNotFoundWithNoBody_ExtractionSucceedsWithNothing() throws {
    StubURLProtocol.behaviour = .respond(statusCode: 404, body: Data())

    let destination = try downloadAndExtract()

    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: destination), [],
      "BUG: a rejected request extracts to an empty directory and is reported as a success")
  }

  // MARK: - Transport errors

  // BUG: a connection dropped mid-transfer is logged and then reported to the
  // extractor as a clean end of file, so the network error is swallowed entirely.
  // Extraction does at least fail, because the archive it was handed is
  // truncated, but all the caller is told is that a process exited non-zero.
  func testDownload_WhenTransportFailsMidStream_SwallowsTheNetworkError() throws {
    let archive = try makeArchiveData(padding: 512 * 1024)
    StubURLProtocol.behaviour = .truncate(
      statusCode: 200, body: archive, bytesBeforeFailure: archive.count / 2)

    XCTAssertThrowsError(try downloadAndExtract()) { error in
      let description = (error as NSError).localizedDescription
      XCTAssertTrue(
        description.localizedCaseInsensitiveContains("exit code"),
        "BUG: the only signal is a non-zero exit, got: \(description)")
      XCTAssertFalse(
        description.localizedCaseInsensitiveContains("network"),
        "BUG: the underlying network error is swallowed, got: \(description)")
      XCTAssertFalse(
        description.localizedCaseInsensitiveContains("connection"),
        "BUG: the underlying network error is swallowed, got: \(description)")
    }
  }
}

// MARK: - Doubles

/// Serves a canned response in place of the network. The behaviour is static
/// because `URLSession` instantiates the protocol itself.
private final class StubURLProtocol: URLProtocol {

  enum Behaviour {
    case none
    case respond(statusCode: Int, body: Data)
    case truncate(statusCode: Int, body: Data, bytesBeforeFailure: Int)
  }

  // SAFETY: set by the test before the request starts and cleared in tearDown,
  // read on the session's delegate queue in between; the two never overlap.
  // patternlint-disable-next-line swift-nonisolated-unsafe
  nonisolated(unsafe) static var behaviour: Behaviour = .none

  override class func canInit(with request: URLRequest) -> Bool {
    return true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  /// The download begins as soon as it is constructed, but the process that
  /// consumes it only attaches its pipe once extraction starts. Delivering
  /// immediately races that attachment, so each step is spaced out -- which is
  /// also how a real transfer behaves.
  private static let step = DispatchTimeInterval.milliseconds(200)

  override func startLoading() {
    guard let url = request.url else { return }
    switch Self.behaviour {
    case .none:
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
    case let .respond(statusCode, body):
      after(Self.step) {
        self.send(response: self.makeResponse(url: url, statusCode: statusCode, length: body.count))
        self.client?.urlProtocol(self, didLoad: body)
        self.client?.urlProtocolDidFinishLoading(self)
      }
    case let .truncate(statusCode, body, bytesBeforeFailure):
      after(Self.step) {
        self.send(response: self.makeResponse(url: url, statusCode: statusCode, length: body.count))
        self.client?.urlProtocol(self, didLoad: body.prefix(bytesBeforeFailure))
        self.after(Self.step) {
          self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        }
      }
    }
  }

  private func after(_ interval: DispatchTimeInterval, _ work: @escaping () -> Void) {
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + interval, execute: work)
  }

  override func stopLoading() {}

  private func makeResponse(url: URL, statusCode: Int, length: Int) -> HTTPURLResponse {
    // swiftlint:disable:next force_unwrapping
    return HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Length": String(length)])!
  }

  private func send(response: HTTPURLResponse) {
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
  }
}

/// A Logger that does nothing.
// SAFETY: stateless no-op.
private final class DownloadTestLogger: NSObject, FBControlCoreLogger, @unchecked Sendable {
  var name: String? { nil }
  var level: FBControlCoreLogLevel { .multiple }

  func log(_ message: String) -> any FBControlCoreLogger { self }
  func info() -> any FBControlCoreLogger { self }
  func debug() -> any FBControlCoreLogger { self }
  func error() -> any FBControlCoreLogger { self }
  func withName(_ name: String) -> any FBControlCoreLogger { self }
  func withDateFormatEnabled(_ enabled: Bool) -> any FBControlCoreLogger { self }
}
