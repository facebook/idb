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
  private func downloadAndExtract() async throws -> String {
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
    let extraction = FBArchiveOperations.extractArchive(
      fromStream: download.input,
      toPath: destination,
      overrideModificationTime: false,
      logger: logger,
      compression: .GZIP)
    // A data consumer carries only bytes and an end of file, so a failed download
    // reaches the extractor as nothing more than a short stream. Its outcome has
    // to be consulted alongside the extraction's.
    try await download.completed()
    return try extraction.`await`() as String
  }

  /// Runs the download and expects it to fail, handing the error to `inspect`.
  private func assertThrows(_ inspect: (Error) -> Void) async {
    do {
      _ = try await downloadAndExtract()
      XCTFail("Expected the download to fail")
    } catch {
      inspect(error)
    }
  }

  // MARK: - Success

  func testDownload_WhenResponseIsOK_ExtractsTheDownloadedArchive() async throws {
    StubURLProtocol.behaviour = .respond(statusCode: 200, body: try makeArchiveData())

    let destination = try await downloadAndExtract()

    XCTAssertEqual(
      try String(
        contentsOfFile: (destination as NSString).appendingPathComponent("payload.txt"),
        encoding: .utf8),
      Self.payloadContents)
  }

  // MARK: - HTTP errors

  func testDownload_WhenResponseIsNotFound_FailsWithTheHTTPStatus() async throws {
    let errorPage = Data("<html><title>404 Not Found</title></html>".utf8)
    StubURLProtocol.behaviour = .respond(statusCode: 404, body: errorPage)

    await assertThrows { error in
      guard case .httpStatus(_, let statusCode)? = error as? FBInstallError else {
        XCTFail("Expected an HTTP status failure, got: \(error)")
        return
      }
      XCTAssertEqual(statusCode, 404)
      XCTAssertTrue(
        (error as NSError).localizedDescription.localizedCaseInsensitiveContains("404"),
        "The description carries the status across the ObjC boundary too")
    }
  }

  func testDownload_WhenResponseIsServerError_FailsWithTheHTTPStatus() async throws {
    StubURLProtocol.behaviour = .respond(
      statusCode: 500, body: Data("internal server error".utf8))

    await assertThrows { error in
      guard case .httpStatus(_, let statusCode)? = error as? FBInstallError else {
        XCTFail("Expected an HTTP status failure, got: \(error)")
        return
      }
      XCTAssertEqual(statusCode, 500)
    }
  }

  /// The case that used to be reported as an outright success: an empty body is a
  /// valid empty archive as far as the extractor is concerned, so nothing
  /// downstream could tell that the request had been rejected.
  func testDownload_WhenResponseIsNotFoundWithNoBody_FailsWithTheHTTPStatus() async throws {
    StubURLProtocol.behaviour = .respond(statusCode: 404, body: Data())

    await assertThrows { error in
      guard case .httpStatus(_, let statusCode)? = error as? FBInstallError else {
        XCTFail("Expected an HTTP status failure, got: \(error)")
        return
      }
      XCTAssertEqual(statusCode, 404)
    }
  }

  // MARK: - Transport errors

  /// Previously reported only as a process exiting non-zero on a truncated
  /// archive, with the transport error logged and discarded.
  func testDownload_WhenTransportFailsMidStream_FailsWithTheNetworkError() async throws {
    let archive = try makeArchiveData(padding: 512 * 1024)
    StubURLProtocol.behaviour = .truncate(
      statusCode: 200, body: archive, bytesBeforeFailure: archive.count / 2)

    await assertThrows { error in
      guard case .transferFailed(_, let underlying)? = error as? FBInstallError else {
        XCTFail("Expected a transfer failure, got: \(error)")
        return
      }
      let nsError = underlying as NSError
      XCTAssertEqual(nsError.domain, NSURLErrorDomain)
      XCTAssertEqual(nsError.code, URLError.Code.networkConnectionLost.rawValue)
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
