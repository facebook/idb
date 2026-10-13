/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency @testable import FBArtifactStaging
@preconcurrency @testable import FBControlCore
import Foundation
import Testing
import os

/// Coverage for extracting a payload of files, rather than an artifact, from a stream.
@Suite(.serialized)
final class StagingExtractTests {

  private let logger: ControlCoreLoggerDouble
  private let scratchRoot: URL

  init() {
    logger = ControlCoreLoggerDouble()
    scratchRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
  }

  deinit {
    try? FileManager.default.removeItem(at: scratchRoot)
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

  @Test
  func aGzippedTarIsExtractedAndItsRouteReported() async throws {
    let input = scratchRoot.appendingPathComponent("input")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try Data("one".utf8).write(to: input.appendingPathComponent("a.txt"))
    try Data("two".utf8).write(to: input.appendingPathComponent("b.txt"))
    try ArchiveFixtures.run("/usr/bin/tar", ["-czf", "../payload.tar.gz", "a.txt", "b.txt"], in: input)
    let events = OSAllocatedUnfairLock<[InstallEvent]>(initialState: [])

    let files = try await extract(try Data(contentsOf: scratchRoot.appendingPathComponent("payload.tar.gz")), events: events)

    #expect(files == ["a.txt": Data("one".utf8), "b.txt": Data("two".utf8)])
    let routes = events.withLock { $0 }.compactMap { event -> ExtractionRoute? in
      guard case .route(let route) = event else { return nil }
      return route
    }
    #expect(routes.map(\.format) == [.gzip])
  }

  @Test
  func anArchiveThatCannotBeExtractedFailsAsAnExtractionFailure() async throws {
    let events = OSAllocatedUnfairLock<[InstallEvent]>(initialState: [])
    var truncated = try GzippingSource(DataSource(Data(repeating: 7, count: 1 << 16))).readAll()
    truncated.removeLast(truncated.count / 2)

    do {
      _ = try await extract(truncated, events: events)
      Issue.record("Expected a truncated archive to fail extraction")
    } catch {
      guard case .extractionFailed? = error as? InstallError else {
        Issue.record("Expected an extraction failure, got: \(error)")
        return
      }
    }
  }
}
