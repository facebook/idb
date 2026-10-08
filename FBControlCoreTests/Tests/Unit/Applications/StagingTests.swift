/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency @testable import FBControlCore
import XCTest
import os

/// Coverage for staging a single gzipped file fetched over HTTP.
final class StagingTests: XCTestCase {

  private var logger: ControlCoreLoggerDouble!
  private var scratchRoot: URL!

  override func setUp() {
    super.setUp()
    logger = ControlCoreLoggerDouble()
    scratchRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
  }

  override func tearDown() {
    StubURLProtocol.behaviour = .none
    try? FileManager.default.removeItem(at: scratchRoot)
    super.tearDown()
  }

  private static var stubbedURL: URL {
    // swiftlint:disable:next force_unwrapping
    // patternlint-disable-next-line use-meta-url-wrapper-for-url
    return URL(string: "https://example.invalid/libSample.dylib.gz")!
  }

  private static let contents = Data((0..<(1 << 18)).map { UInt8(truncatingIfNeeded: $0 &* 31) })

  /// Stages the stubbed URL as `libSample.dylib`, returning what was staged and the progress reported.
  private func stageRemoteGzippedFile() async throws -> (name: String, contents: Data, events: [InstallProgressEvent]) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let events = OSAllocatedUnfairLock<[InstallProgressEvent]>(initialState: [])
    let staged = try await Staging.withMaterialized(
      .remoteGzippedFile(Self.stubbedURL, name: "libSample.dylib"),
      as: .dylib,
      downloadConfiguration: configuration,
      temporaryDirectory: TemporaryDirectory(rootDirectory: scratchRoot, logger: logger),
      logger: logger,
      onProgress: { event in events.withLock { $0.append(event) } }
    ) { tree in
      guard case .file(let file) = tree else {
        XCTFail("Expected a single staged file, got \(tree)")
        return ("", Data())
      }
      return (file.lastPathComponent, try Data(contentsOf: file))
    }
    return (staged.0, staged.1, events.withLock { $0 })
  }

  func testAGzippedFileIsDownloadedAndInflatedUnderItsName() async throws {
    StubURLProtocol.behaviour = .respond(statusCode: 200, body: try GzippingSource(DataSource(Self.contents)).readAll())

    let (name, contents, _) = try await stageRemoteGzippedFile()

    XCTAssertEqual(name, "libSample.dylib")
    XCTAssertEqual(contents, Self.contents)
  }

  func testAGzippedFileReportsItsDownloadAndDecompression() async throws {
    let gzipped = try GzippingSource(DataSource(Self.contents)).readAll()
    StubURLProtocol.behaviour = .respond(statusCode: 200, body: gzipped)

    let (_, _, events) = try await stageRemoteGzippedFile()

    let ordering = events.map { "\($0.stage.rawValue).\($0.phase.rawValue)" }
    XCTAssertEqual(
      ordering.filter { $0.hasSuffix(".started") || $0.hasSuffix(".completed") },
      ["download.started", "extract.started", "download.completed", "extract.completed"],
      "Got: \(ordering)")
    let completion = events.compactMap { event -> Int64? in
      guard case .downloadCompleted(_, let totalBytes) = event else { return nil }
      return totalBytes
    }
    XCTAssertEqual(completion, [Int64(gzipped.count)])
  }

  /// A truncated transfer inflates as a gzip that ends early; the transfer's own failure is what reaches the caller.
  func testAGzippedFileWhoseTransferFailsFailsWithTheTransferError() async throws {
    let gzipped = try GzippingSource(DataSource(Self.contents)).readAll()
    StubURLProtocol.behaviour = .truncate(statusCode: 200, body: gzipped, bytesBeforeFailure: gzipped.count / 2)

    do {
      _ = try await stageRemoteGzippedFile()
      XCTFail("Expected the failed transfer to fail staging")
    } catch {
      guard case .transferFailed? = error as? InstallError else {
        return XCTFail("Expected a transfer failure, got: \(error)")
      }
    }
  }
}
