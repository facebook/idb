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

/// Archives that try to write outside the directory they are extracted into, through every way a zip is extracted.
/// Each is refused, and nothing lands outside the destination.
@Suite
struct UnsafeArchiveTests {

  typealias Entry = ZipBuilder.Entry

  /// How a zip is extracted.
  enum Route: String, CaseIterable, CustomTestStringConvertible {
    /// `ZipExtractor` reading the complete file.
    case file
    /// `ZipStreamExtractor` reading it as it arrives, then the repair from the complete file.
    case streamThenRepair
    /// The sniffing extractor reading it as a stream, as an install does.
    case sniffing

    var testDescription: String { rawValue }
  }

  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let entries: @Sendable (_ outside: String) -> [Entry]
    var testDescription: String { name }
  }

  static let cases: [Case] = [
    Case(name: "absolute path") { outside in [.file("A.app/Info.plist"), .file(outside + "/escaped")] },
    Case(name: "parent traversal") { _ in [.file("A.app/Info.plist"), .file("A.app/../../escaped")] },
    Case(name: "symlink ancestor, link first") { outside in
      [.directory("A.app"), .symlink("A.app/link", to: outside), .file("A.app/link/escaped")]
    },
    Case(name: "symlink ancestor, link last") { outside in
      [.directory("A.app"), .file("A.app/link/escaped"), .symlink("A.app/link", to: outside)]
    },
  ]

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let logger = ControlCoreGlobalConfiguration.defaultLogger

  private func extract(_ zip: Data, at archive: URL, to destination: String, by route: Route) async throws {
    switch route {
    case .file:
      _ = try ZipExtractor.extract(archiveAtPath: archive.path, to: destination)
    case .streamThenRepair:
      _ = try ZipStreamExtractor.extract(from: DataSource(zip), to: destination)
      try ZipCentralDirectory(archiveAtPath: archive.path).repair(extractedAt: destination)
    case .sniffing:
      let spool = root.appendingPathComponent("spool-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true)
      try await ArchiveExtractors.inProcess.extract(
        from: DataSource(zip, pieceSize: 1000), spoolingIn: spool, to: destination, options: ArchiveExtractOptions(), logger: logger
      ) { _ in }
    }
  }

  @Test(arguments: cases, Route.allCases)
  func anEntryEscapingTheDestinationIsRefused(_ unsafe: Case, _ route: Route) async throws {
    let outside = root.appendingPathComponent("outside-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let destination = root.appendingPathComponent("extracted-\(UUID().uuidString)/nested/deeper")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let zip = ZipBuilder.zip(unsafe.entries(outside.path))
    let archive = root.appendingPathComponent("unsafe-\(UUID().uuidString).zip")
    try zip.write(to: archive)

    if Self.stripsTheLeadingSlash(unsafe, route) {
      try await extract(zip, at: archive, to: destination.path, by: route)
    } else {
      await #expect(throws: (any Error).self, "\(unsafe.name) through \(route)") {
        try await extract(zip, at: archive, to: destination.path, by: route)
      }
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty, "\(unsafe.name) through \(route) wrote outside")
    let escaped = destination.appendingPathComponent("../../escaped").standardizedFileURL.path
    #expect(!FileManager.default.fileExists(atPath: escaped), "\(unsafe.name) through \(route) wrote \(escaped)")
  }

  /// CURRENT: the in-process extractors refuse an absolute name, and the sniffing extractor then falls back to `bsdtar`,
  /// which extracts it as `bsdtar` always does: with the leading `/` stripped, inside the destination.
  static func stripsTheLeadingSlash(_ unsafe: Case, _ route: Route) -> Bool {
    unsafe.name == "absolute path" && route == .sniffing
  }

  @Test(arguments: Route.allCases)
  func theSameZipWithoutTheEscapingEntryExtracts(_ route: Route) async throws {
    let zip = ZipBuilder.zip([.directory("A.app"), .file("A.app/Info.plist"), .symlink("A.app/link", to: "Info.plist")])
    let archive = root.appendingPathComponent("safe.zip")
    try zip.write(to: archive)
    let destination = root.appendingPathComponent("safe-\(route.rawValue)")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try await extract(zip, at: archive, to: destination.path, by: route)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("A.app/link").path) == "Info.plist")
  }

  /// CURRENT: nothing bounds what an archive expands to. A gzipped tar of 64 MiB of zeros, about 64 KiB on the wire,
  /// extracts in full. If a bound is added, this is where it is pinned.
  @Test
  func nothingBoundsWhatAnArchiveExpandsTo() async throws {
    let source = root.appendingPathComponent("bomb")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data(count: 64 << 20).write(to: source.appendingPathComponent("zeros"))
    let archive = root.appendingPathComponent("bomb.tar.gz")
    try ArchiveFixtures.run("/usr/bin/tar", ["-czf", archive.path, "bomb"], in: root)
    let compressed = try Data(contentsOf: archive)
    #expect(compressed.count < 1 << 20)
    let destination = root.appendingPathComponent("bomb-extracted")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try await ArchiveExtractors.inProcess.extract(
      from: DataSource(compressed), to: destination.path, options: ArchiveExtractOptions(), logger: logger)
    let size = try FileManager.default.attributesOfItem(atPath: destination.appendingPathComponent("bomb/zeros").path)[.size] as? Int
    #expect(size == 64 << 20)
  }
}
