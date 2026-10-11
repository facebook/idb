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
import os

/// Every kind of artifact through every way staging can get it: what it identifies, whether it is in place, and the
/// stages it reports. Where kinds behave differently today the difference is spelt out, so that making them uniform
/// shows up as a change to an expectation here.
@Suite
struct InstallMatrixTests {

  /// Where an artifact comes from.
  enum Source: String, CaseIterable, CustomTestStringConvertible {
    /// A path to the artifact itself.
    case path
    /// A path to a zip of the artifact.
    case pathToZip
    /// A zip arriving on a pipe.
    case streamedZip
    /// A gzipped tar arriving on a pipe.
    case streamedTarGzip
    /// A zip over HTTP.
    case remoteZip
    /// A gzipped tar over HTTP.
    case remoteTarGzip
    /// A single gzipped file on a pipe, staged under its name.
    case streamedGzippedFile
    /// A single gzipped file over HTTP, staged under its name.
    case remoteGzippedFile

    var testDescription: String { rawValue }

    /// The single-file sources exist for dylibs alone.
    func applies(to kind: Kind) -> Bool {
      switch self {
      case .streamedGzippedFile, .remoteGzippedFile:
        return kind == .dylib
      case .path, .pathToZip, .streamedZip, .streamedTarGzip, .remoteZip, .remoteTarGzip:
        return true
      }
    }
  }

  enum Kind: String, CaseIterable, CustomTestStringConvertible {
    case application
    case xctest
    case framework
    case dylib
    case dsym

    var testDescription: String { rawValue }

    var artifactKind: ArtifactKind {
      switch self {
      case .application:
        return .application
      case .xctest:
        return .xctest
      case .framework:
        return .framework
      case .dylib:
        return .dylib
      case .dsym:
        return .dsym
      }
    }

    /// The name of the item that stands for this kind on disk.
    var itemName: String {
      switch self {
      case .application:
        return "A.app"
      case .xctest:
        return "T.xctest"
      case .framework:
        return "F.framework"
      case .dylib:
        return "libX.dylib"
      case .dsym:
        return "X.dSYM"
      }
    }
  }

  /// What staging made of a source.
  enum Outcome: Equatable, CustomStringConvertible {
    /// The artifact's case and item name, whether it was in place, and the stages reported.
    case installed(artifact: String, inPlace: Bool, stages: [String])
    case failed(String)

    var description: String {
      switch self {
      case .installed(let artifact, let inPlace, let stages):
        return "\(artifact)\(inPlace ? " in place" : "") \(stages)"
      case .failed(let reason):
        return "failed: \(reason)"
      }
    }
  }

  private static var cases: [(Kind, Source)] {
    Kind.allCases.flatMap { kind in Source.allCases.filter { $0.applies(to: kind) }.map { (kind, $0) } }
  }

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let logger = ControlCoreGlobalConfiguration.defaultLogger

  // MARK: - Fixtures

  private func makeItem(_ kind: Kind) throws -> URL {
    let fileManager = FileManager.default
    let item = root.appendingPathComponent(kind.itemName)
    switch kind {
    case .application, .framework:
      try fileManager.createDirectory(at: item, withIntermediateDirectories: true)
      let executable = kind == .application ? "A" : "F"
      try fileManager.copyItem(atPath: "/bin/ls", toPath: item.appendingPathComponent(executable).path)
      let plist: [String: Any] = [
        "CFBundleIdentifier": "com.example.matrix.\(kind.rawValue)", "CFBundleName": executable, "CFBundleExecutable": executable,
        "CFBundlePackageType": kind == .application ? "APPL" : "FMWK",
      ]
      try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: item.appendingPathComponent("Info.plist"))
    case .xctest, .dsym:
      try fileManager.createDirectory(at: item.appendingPathComponent("Contents"), withIntermediateDirectories: true)
      try Data("<plist/>".utf8).write(to: item.appendingPathComponent("Contents/Info.plist"))
    case .dylib:
      try Data("not really a dylib".utf8).write(to: item)
    }
    return item
  }

  private func source(_ source: Source, for kind: Kind) throws -> (InstallSource, URLSessionConfiguration) {
    let item = try makeItem(kind)
    let zip = root.appendingPathComponent("item.zip")
    let tarGzip = root.appendingPathComponent("item.tar.gz")
    try ArchiveFixtures.run("/usr/bin/zip", ["-qry", zip.path, kind.itemName], in: root)
    try ArchiveFixtures.run("/usr/bin/tar", ["-czf", tarGzip.path, kind.itemName], in: root)
    switch source {
    case .path:
      return (.localPath(item.path), .default)
    case .pathToZip:
      return (.localPath(zip.path), .default)
    case .streamedZip:
      return (.stream(ChunkSource(try Data(contentsOf: zip))), .default)
    case .streamedTarGzip:
      return (.stream(ChunkSource(try Data(contentsOf: tarGzip))), .default)
    case .remoteZip:
      return (.remoteURL(CorpusURLProtocol.serving(try Data(contentsOf: zip))), CorpusURLProtocol.configuration)
    case .remoteTarGzip:
      return (.remoteURL(CorpusURLProtocol.serving(try Data(contentsOf: tarGzip))), CorpusURLProtocol.configuration)
    case .streamedGzippedFile:
      let gzipped = try GzippingSource(DataSource(try Data(contentsOf: item))).readAll()
      return (.gzippedFile(ChunkSource(gzipped), name: kind.itemName), .default)
    case .remoteGzippedFile:
      let gzipped = try GzippingSource(DataSource(try Data(contentsOf: item))).readAll()
      return (.remoteGzippedFile(CorpusURLProtocol.serving(gzipped), name: kind.itemName), CorpusURLProtocol.configuration)
    }
  }

  private static func describe(_ artifact: Artifact) -> String {
    switch artifact {
    case .application(let bundle):
      return "application \(URL(fileURLWithPath: bundle.path).lastPathComponent)"
    case .framework(let bundle):
      return "framework \(URL(fileURLWithPath: bundle.path).lastPathComponent)"
    case .testBundle(let url):
      return "testBundle \(url.lastPathComponent)"
    case .testRun(let url):
      return "testRun \(url.lastPathComponent)"
    case .dylib(let url):
      return "dylib \(url.lastPathComponent)"
    case .dsym(let url):
      return "dsym \(url.lastPathComponent)"
    }
  }

  private func stage(_ kind: Kind, from sourceCase: Source) async throws -> Outcome {
    let (installSource, configuration) = try source(sourceCase, for: kind)
    let stages = OSAllocatedUnfairLock<[String]>(initialState: [])
    do {
      let (artifact, inPlace) = try await Staging.install(
        installSource, as: kind.artifactKind, downloadConfiguration: configuration,
        temporaryDirectory: TemporaryDirectory(rootDirectory: root.appendingPathComponent("staging"), logger: logger), logger: logger,
        onProgress: { event in
          guard event.phase == .started || event.phase == .completed else {
            return
          }
          stages.withLock { $0.append("\(event.stage.rawValue).\(event.phase.rawValue)") }
        },
        name: { (installed: (String, Bool)) in installed.0 }
      ) { artifact, inPlace in
        (Self.describe(artifact), inPlace)
      }
      return .installed(artifact: artifact, inPlace: inPlace, stages: stages.withLock { $0 })
    } catch {
      return .failed("\(type(of: error))")
    }
  }

  // MARK: - Expectations

  private static func artifactName(_ kind: Kind) -> String {
    switch kind {
    case .application:
      return "application A.app"
    case .xctest:
      return "testBundle T.xctest"
    case .framework:
      return "framework F.framework"
    case .dylib:
      return "dylib libX.dylib"
    case .dsym:
      return "dsym X.dSYM"
    }
  }

  private static func expected(_ kind: Kind, _ source: Source) -> Outcome {
    let unpacked = ["extract.started", "extract.completed", "install.started", "install.completed"]
    let downloaded = ["download.started", "extract.started", "download.completed", "extract.completed", "install.started", "install.completed"]
    switch (kind, source) {
    case (_, .path):
      return .installed(artifact: artifactName(kind), inPlace: true, stages: ["install.started", "install.completed"])
    case (.application, .pathToZip):
      return .installed(artifact: artifactName(kind), inPlace: false, stages: unpacked)
    // CURRENT: only an application's local path may be an archive. Any other kind takes the zip itself as the
    // artifact, in place: a dylib or dSYM is "identified" as the zip, a test bundle or framework is refused.
    case (.dylib, .pathToZip):
      return .installed(artifact: "dylib item.zip", inPlace: true, stages: ["install.started", "install.completed"])
    case (.dsym, .pathToZip):
      return .installed(artifact: "dsym item.zip", inPlace: true, stages: ["install.started", "install.completed"])
    case (.xctest, .pathToZip):
      return .failed("ArtifactError")
    case (.framework, .pathToZip):
      return .failed("BundleError")
    case (_, .streamedZip), (_, .streamedTarGzip), (.dylib, .streamedGzippedFile):
      return .installed(artifact: artifactName(kind), inPlace: false, stages: unpacked)
    case (_, .remoteZip), (_, .remoteTarGzip), (.dylib, .remoteGzippedFile):
      return .installed(artifact: artifactName(kind), inPlace: false, stages: downloaded)
    case (_, .streamedGzippedFile), (_, .remoteGzippedFile):
      preconditionFailure("single-file sources are for dylibs")
    }
  }

  @Test(arguments: cases)
  func stagesEveryKindFromEverySource(_ kind: Kind, _ source: Source) async throws {
    let outcome = try await stage(kind, from: source)
    let expected = Self.expected(kind, source)
    switch (expected, outcome) {
    case (.failed, .failed(let reason)):
      // The error types are not public API; that it fails, and before installing, is what is pinned.
      #expect(!reason.isEmpty)
    case (.installed(let artifact, let inPlace, let stages), .installed(let actualArtifact, let actualInPlace, let actualStages)):
      #expect(actualArtifact == artifact, "\(kind) \(source)")
      #expect(actualInPlace == inPlace, "\(kind) \(source)")
      #expect(actualStages == stages, "\(kind) \(source)")
    case (.installed, .failed), (.failed, .installed):
      Issue.record("\(kind) \(source): expected \(expected), got \(outcome)")
    }
  }
}
