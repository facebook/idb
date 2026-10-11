/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency @testable import FBArtifactStaging
@preconcurrency @testable import FBControlCore
import XCTest
import os

/// Coverage for extracting a payload of files, rather than an artifact, from a stream.
final class StagingExtractTests: XCTestCase {

  private var logger: ControlCoreLoggerDouble!
  private var scratchRoot: URL!

  override func setUp() {
    super.setUp()
    logger = ControlCoreLoggerDouble()
    scratchRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: scratchRoot)
    super.tearDown()
  }

  private func extract(_ archive: Data, events: OSAllocatedUnfairLock<[InstallEvent]>) async throws -> [String: Data] {
    try await Staging.extract(
      ChunkSource(archive),
      temporaryDirectory: TemporaryDirectory(rootDirectory: scratchRoot, logger: logger),
      logger: logger,
      onEvent: { event in events.withLock { $0.append(event) } }
    ) { directory in
      let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      return try Dictionary(uniqueKeysWithValues: names.map { ($0, try Data(contentsOf: directory.appendingPathComponent($0))) })
    }
  }

  func testAGzippedTarIsExtractedAndItsRouteReported() async throws {
    let input = scratchRoot.appendingPathComponent("input")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try Data("one".utf8).write(to: input.appendingPathComponent("a.txt"))
    try Data("two".utf8).write(to: input.appendingPathComponent("b.txt"))
    try ArchiveFixtures.run("/usr/bin/tar", ["-czf", "../payload.tar.gz", "a.txt", "b.txt"], in: input)
    let events = OSAllocatedUnfairLock<[InstallEvent]>(initialState: [])

    let files = try await extract(try Data(contentsOf: scratchRoot.appendingPathComponent("payload.tar.gz")), events: events)

    XCTAssertEqual(files, ["a.txt": Data("one".utf8), "b.txt": Data("two".utf8)])
    let routes = events.withLock { $0 }.compactMap { event -> ExtractionRoute? in
      guard case .route(let route) = event else { return nil }
      return route
    }
    XCTAssertEqual(routes.map(\.format), [.gzip])
  }

  func testAnArchiveThatCannotBeExtractedFailsAsAnExtractionFailure() async throws {
    let events = OSAllocatedUnfairLock<[InstallEvent]>(initialState: [])
    var truncated = try GzippingSource(DataSource(Data(repeating: 7, count: 1 << 16))).readAll()
    truncated.removeLast(truncated.count / 2)

    do {
      _ = try await extract(truncated, events: events)
      XCTFail("Expected a truncated archive to fail extraction")
    } catch {
      guard case .extractionFailed? = error as? InstallError else {
        return XCTFail("Expected an extraction failure, got: \(error)")
      }
    }
  }
}
