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

/// Every archive producer, through every way an archive reaches an extractor, checked against what `bsdtar` extracts from the same file.
@Suite
struct ArchiveCorpusTests {

  typealias Producer = ArchiveCorpus.Producer

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let temporaryDirectory = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger)
  private let logger = ControlCoreGlobalConfiguration.defaultLogger
  private var corpus: ArchiveCorpus { ArchiveCorpus(root: root) }

  /// How an archive reaches an extractor.
  enum Route: String, CaseIterable, CustomTestStringConvertible {
    /// `ArchiveExtractors.default` given the archive's path.
    case file
    /// `ArchiveExtractors.default` reading the archive as a stream.
    case stream
    /// `ZipStreamExtractor` reading a zip as it arrives, then repairing it from the complete file.
    case zipStream

    var testDescription: String { rawValue }

    func reads(_ producer: Producer) -> Bool {
      switch self {
      case .file, .stream:
        return true
      case .zipStream:
        return producer.isZip
      }
    }

    /// Whether a zip is read as it arrives, then repaired from the complete file.
    func repairsAZip(_ producer: Producer) -> Bool {
      self != .file && producer.isZip
    }

    /// Whether the archive is extracted in-process, rather than handed on to `bsdtar`.
    func extractsInProcess(_ producer: Producer) -> Bool {
      switch self {
      case .file, .zipStream:
        return producer.isZip
      case .stream:
        return true
      }
    }
  }

  private static var extractorCases: [(Producer, Route)] {
    Producer.allCases.flatMap { producer in Route.allCases.filter { $0.reads(producer) }.map { (producer, $0) } }
  }

  private func bsdtarOutcome(_ archive: URL, keepHardLinks: Bool, directoryTimes: Bool = true) async -> Outcome {
    let expected = root.appendingPathComponent("bsdtar-\(UUID().uuidString)").path
    do {
      try FileManager.default.createDirectory(atPath: expected, withIntermediateDirectories: true)
      try await BSDTarExtractor().extract(fromFile: archive.path, to: expected, options: ArchiveExtractOptions(), logger: logger)
      let tree = try ArchiveFixtures.bsdtarTree(at: expected, keepHardLinks: keepHardLinks, directoryTimes: directoryTimes)
      // An empty archive is no app, which an install rightly refuses.
      return tree.isEmpty ? .failed("nothing extracted") : .extracted(tree)
    } catch {
      return .failed("\(error)")
    }
  }

  // MARK: - Extractors

  @Test(arguments: extractorCases)
  func anExtractorMatchesBSDTar(_ producer: Producer, _ route: Route) async throws {
    do {
      try await extractorMatchesBSDTar(producer, route)
    } catch {
      Issue.record("\(producer) \(route): \(error)")
    }
  }

  private func extractorMatchesBSDTar(_ producer: Producer, _ route: Route) async throws {
    try corpus.makeApp()
    let archive = try corpus.archive(producer)
    let extracted = root.appendingPathComponent("extracted").path
    try FileManager.default.createDirectory(atPath: extracted, withIntermediateDirectories: true)
    let fallback = RecordingExtractor(BSDTarExtractor())
    let tarExtractor = InProcessTarExtractor(fallback: fallback)
    let extractor = SniffingExtractor(files: InProcessZipExtractor(fallback: tarExtractor), tars: tarExtractor)

    switch route {
    case .file:
      try await extractor.extract(fromFile: archive.path, to: extracted, options: ArchiveExtractOptions(), logger: logger)
    case .stream:
      try await BytePipe(try Data(contentsOf: archive)).reading {
        try await extractor.extract(from: $0, to: extracted, options: ArchiveExtractOptions(), logger: logger)
      }
    case .zipStream:
      try await BytePipe(try Data(contentsOf: archive)).reading { source in
        let source = HandedOver(source)
        _ = try await offCooperativePool { try ZipStreamExtractor.extract(from: source.value, to: extracted) }.get()
      }
      try ZipCentralDirectory(archiveAtPath: archive.path).repair(extractedAt: extracted)
    }

    // The repair removes AppleDouble files after the fact, which moves their directories' times.
    let directoryTimes = !route.repairsAZip(producer)
    let expected = await bsdtarOutcome(archive, keepHardLinks: producer.keepsHardLinks, directoryTimes: directoryTimes)
    let actual = try ArchiveFixtures.tree(at: extracted, keepHardLinks: producer.keepsHardLinks, directoryTimes: directoryTimes)
    guard case .extracted(let expectedTree) = expected else {
      Issue.record("bsdtar could not extract \(producer)")
      return
    }
    #expect(ArchiveFixtures.differences(expectedTree, actual) == "", "\(producer) \(route)")
    #expect(fallback.wasReached != route.extractsInProcess(producer), "\(producer) \(route) fell back: \(fallback.wasReached)")
  }

  // MARK: - Installs

  /// How an install hands `ApplicationArchive` an archive.
  enum Source: String, CaseIterable, CustomTestStringConvertible {
    case localPath
    case stream
    case remoteURL

    var testDescription: String { rawValue }
  }

  /// What an extraction left behind, or that it failed.
  enum Outcome: Equatable, CustomStringConvertible {
    case extracted([String: String])
    case failed(String)

    var description: String {
      switch self {
      case .extracted(let tree):
        return "extracted \(tree.count) items"
      case .failed(let reason):
        return "failed: \(reason)"
      }
    }
  }

  private func installSource(_ source: Source, archive: URL, contents: Data) -> (InstallSource, URLSessionConfiguration) {
    switch source {
    case .localPath:
      return (.localPath(archive.path), .default)
    case .stream:
      return (.stream(BytePipe(contents)), .default)
    case .remoteURL:
      return (.remoteURL(CorpusURLProtocol.serving(contents)), CorpusURLProtocol.configuration)
    }
  }

  /// Resolves `contents` through `source`, as the tree beside the bundle it finds.
  private func resolve(_ source: Source, archive: URL, contents: Data, keepHardLinks: Bool, directoryTimes: Bool) async throws -> Outcome {
    let (installSource, configuration) = installSource(source, archive: archive, contents: contents)
    do {
      return try await Staging.withMaterialized(
        installSource, as: .application, downloadConfiguration: configuration, temporaryDirectory: temporaryDirectory, logger: logger
      ) { tree in
        let bundle = try Artifact.applicationBundle(in: tree, logger: logger)
        return .extracted(try ArchiveFixtures.tree(at: (bundle.path as NSString).deletingLastPathComponent, keepHardLinks: keepHardLinks, directoryTimes: directoryTimes))
      }
    } catch InstallError.extractionFailed(let underlying) {
      return .failed("\(underlying)")
    } catch {
      return .failed("\(error)")
    }
  }

  private static var installCases: [(Producer, Source)] {
    Producer.allCases.flatMap { producer in Source.allCases.map { (producer, $0) } }
  }

  @Test(arguments: installCases)
  func anInstallMatchesBSDTar(_ producer: Producer, _ source: Source) async throws {
    try corpus.makeApp()
    let archive = try corpus.archive(producer)
    let directoryTimes = !producer.isZip

    let actual = try await resolve(source, archive: archive, contents: try Data(contentsOf: archive), keepHardLinks: producer.keepsHardLinks, directoryTimes: directoryTimes)

    let expected = await bsdtarOutcome(archive, keepHardLinks: producer.keepsHardLinks, directoryTimes: directoryTimes)
    guard case .extracted(let expectedTree) = expected, case .extracted(let actualTree) = actual else {
      Issue.record("\(producer): bsdtar \(expected), \(source) \(actual)")
      return
    }
    #expect(ArchiveFixtures.differences(expectedTree, actualTree) == "", "\(producer) \(source)")
  }

  // MARK: - Damaged archives

  enum Damage: CustomTestStringConvertible {
    /// Cut to this fraction of its length.
    case truncated(Double)
    /// One byte inverted, at this fraction of its length.
    case flipped(Double)

    func apply(to contents: Data) -> Data {
      switch self {
      case .truncated(let fraction):
        return contents.prefix(Int(Double(contents.count) * fraction))
      case .flipped(let fraction):
        var damaged = contents
        let offset = min(Int(Double(contents.count) * fraction), contents.count - 1)
        damaged[damaged.startIndex + offset] ^= 0xFF
        return damaged
      }
    }

    var testDescription: String {
      switch self {
      case .truncated(let fraction):
        return "truncated to \(fraction)"
      case .flipped(let fraction):
        return "flipped at \(fraction)"
      }
    }
  }

  private static var damages: [Damage] {
    var generator = SplitMix64(seed: 11)
    return [0.0, 0.01, 0.5, 0.99, 0.999_9].map(Damage.truncated) + (0..<6).map { _ in .flipped(Double.random(in: 0..<1, using: &generator)) } + [.flipped(0.999_9)]
  }

  private static var damageCases: [(Producer, Damage)] {
    [Producer.dittoZip, .zipToAPipe, .tarGzip, .tarUncompressed].flatMap { producer in damages.map { (producer, $0) } }
  }

  /// A zip records each time in both its local header and its central directory, checking neither, so a byte flipped in one copy leaves `bsdtar`, which reads the local header, and the in-process extractor, which reads the central directory, disagreeing on the time.
  private static func withoutTimes(_ tree: [String: String]) -> [String: String] {
    tree.mapValues { entry in
      var fields = entry.split(separator: " ")
      guard fields.count > 2, fields[0] == "file" || fields[0] == "dir" else {
        return entry
      }
      fields.remove(at: 2)
      return fields.joined(separator: " ")
    }
  }

  /// An install of a damaged archive ends as `bsdtar` does: failing, or with the same tree. It may also fail as corrupt where `bsdtar` extracts regardless, as `bsdtar` does not check a gzip's CRC and skips a damaged header.
  @Test(arguments: damageCases)
  func aDamagedInstallEndsAsBSDTarDoes(_ producer: Producer, _ damage: Damage) async throws {
    try corpus.makeApp()
    let damaged = damage.apply(to: try Data(contentsOf: try corpus.archive(producer)))
    let archive = root.appendingPathComponent("damaged")
    try damaged.write(to: archive)
    let directoryTimes = !producer.isZip
    let expected = await bsdtarOutcome(archive, keepHardLinks: producer.keepsHardLinks, directoryTimes: directoryTimes)

    for source in Source.allCases {
      let actual = try await resolve(source, archive: archive, contents: damaged, keepHardLinks: producer.keepsHardLinks, directoryTimes: directoryTimes)
      switch (expected, actual) {
      case (.extracted(let expectedTree), .extracted(let actualTree)):
        let compared = producer.isZip ? (Self.withoutTimes(expectedTree), Self.withoutTimes(actualTree)) : (expectedTree, actualTree)
        #expect(ArchiveFixtures.differences(compared.0, compared.1) == "", "\(producer) \(damage) \(source)")
      case (.failed, .failed):
        break
      case (.extracted, .failed(let reason)):
        #expect(reason.hasPrefix("corrupt("), "\(producer) \(damage) \(source): bsdtar extracted it, install \(actual)")
      case (.failed, .extracted):
        Issue.record("\(producer) \(damage) \(source): bsdtar \(expected), install \(actual)")
      }
    }
  }
}
