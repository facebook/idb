/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBArtifactStaging
@testable import FBControlCore
import Foundation
import Testing

/// A source that fails part way through an archive, on every route an archive can be extracted by. Whatever the route,
/// the extraction has to fail and say why: the source's own failure, rather than a corrupt archive or a fallback
/// that hides it.
@Suite
struct ExtractionUpstreamFailureTests {

  /// How an archive streams into extraction.
  enum Route: String, CaseIterable, CustomTestStringConvertible {
    /// A zip, extracted as it arrives and repaired from its spooled copy.
    case zipStream
    /// A gzipped tar, extracted in-process.
    case inProcessTar
    /// A gzipped tar, handed on to `bsdtar`.
    case bsdTar

    var testDescription: String { rawValue }

    var extractor: SniffingExtractor {
      switch self {
      case .zipStream, .inProcessTar:
        return ArchiveExtractors.inProcess
      case .bsdTar:
        return ArchiveExtractors.stream(.GZIP)
      }
    }
  }

  /// Where in the archive the source fails, as a fraction of its length.
  enum Point: String, CaseIterable, CustomTestStringConvertible {
    case start
    case header
    case middle
    case lastByte

    var testDescription: String { rawValue }

    func offset(in count: Int) -> Int {
      switch self {
      case .start:
        return 0
      case .header:
        return 10
      case .middle:
        return count / 2
      case .lastByte:
        return count - 1
      }
    }
  }

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let logger = ControlCoreGlobalConfiguration.defaultLogger

  private func archive(for route: Route) throws -> Data {
    let app = try ArchiveFixtures.makeApp(in: root)
    let archive = root.appendingPathComponent("archive")
    switch route {
    case .zipStream:
      try ArchiveFixtures.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive.path], in: root)
    case .inProcessTar, .bsdTar:
      try ArchiveFixtures.run("/usr/bin/tar", ["-czf", archive.path, "A.app"], in: root)
    }
    return try Data(contentsOf: archive)
  }

  private func extract(_ source: any ByteSource, by route: Route) async throws {
    let destination = root.appendingPathComponent("extracted-\(UUID().uuidString)")
    let spool = root.appendingPathComponent("spool-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true)
    try await route.extractor.extract(
      from: source, spoolingIn: spool, to: destination.path, options: ArchiveExtractOptions(), logger: logger
    ) { _ in }
  }

  @Test(arguments: Route.allCases, Point.allCases)
  func aFailingSourceFailsTheExtractionWithItsOwnError(_ route: Route, _ point: Point) async throws {
    let data = try archive(for: route)
    let source = FailingSource(data, failingAt: point.offset(in: data.count))
    let error = await #expect(throws: (any Error).self) {
      try await extract(source, by: route)
    }
    #expect(Self.carriesInjectedFailure(error), "\(route) failing at \(point) threw \(String(describing: error))")
  }

  @Test(arguments: Route.allCases)
  func theWholeArchiveExtracts(_ route: Route) async throws {
    let data = try archive(for: route)
    try await extract(DataSource(data, pieceSize: 4096), by: route)
  }

  /// Whether `error` is the injected failure or names it, as an error that wraps another describes it.
  static func carriesInjectedFailure(_ error: (any Error)?) -> Bool {
    guard let error else {
      return false
    }
    return error is InjectedFailure || "\(error)".contains(InjectedFailure().description)
  }
}
