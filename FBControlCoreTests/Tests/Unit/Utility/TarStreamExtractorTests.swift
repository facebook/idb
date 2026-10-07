/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing
import os

@Suite
struct TarStreamExtractorTests {

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let fileManager = FileManager.default
  private let logger = ControlCoreGlobalConfiguration.defaultLogger

  private func run(_ launchPath: String, _ arguments: [String]) throws {
    try ArchiveFixtures.run(launchPath, arguments, in: root)
  }

  /// An app with modes, symlinks, a hard link, long and non-ASCII names, and an
  /// extended attribute, which macOS `tar` stores in both a pax header and an
  /// AppleDouble entry.
  private func makeApp() throws -> String {
    let app = root.appendingPathComponent("A.app")
    let long = "Real/" + String(repeating: "nested-directory/", count: 8) + "ünïcode-file-with-a-long-name.txt"
    try fileManager.createDirectory(at: app.appendingPathComponent((long as NSString).deletingLastPathComponent), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: app.appendingPathComponent("Private"), withIntermediateDirectories: true)
    try Data("binary".utf8).write(to: app.appendingPathComponent("A"))
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent("A").path)
    try Data("<plist/>".utf8).write(to: app.appendingPathComponent("Info.plist"))
    try Data(String(repeating: "compressible ", count: 600_000).utf8).write(to: app.appendingPathComponent("big.txt"))
    try Data("long".utf8).write(to: app.appendingPathComponent(long))
    try Data().write(to: app.appendingPathComponent("Real/empty"))
    try Data("secret".utf8).write(to: app.appendingPathComponent("Private/key"))
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: app.appendingPathComponent("Private/key").path)
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: app.appendingPathComponent("Private").path)
    try fileManager.createSymbolicLink(atPath: app.appendingPathComponent("link.plist").path, withDestinationPath: "Info.plist")
    try fileManager.createSymbolicLink(atPath: app.appendingPathComponent("LinkDir").path, withDestinationPath: "Real")
    try fileManager.linkItem(atPath: app.appendingPathComponent("A").path, toPath: app.appendingPathComponent("Hardlink").path)
    try run("/usr/bin/xattr", ["-w", "com.example.tag", "value", app.appendingPathComponent("Info.plist").path])
    return app.path
  }

  private func tree(at path: String) throws -> [String: String] {
    try ArchiveFixtures.tree(at: path, linkTimes: true)
  }

  /// Writes `contents` to a pipe in small pieces, as an archive arrives, and
  /// extracts what is read from it.
  private func extractFromPipe(_ contents: Data, to extracted: String, overrideModificationTime: Bool = false) throws -> TarStreamExtractor.Outcome {
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)
    var fds: [Int32] = [0, 0]
    #expect(pipe(&fds) == 0)
    let (readEnd, writeEnd) = (fds[0], fds[1])
    _ = fcntl(writeEnd, F_SETNOSIGPIPE, 1)
    let finished = DispatchSemaphore(value: 0)
    defer { finished.wait() }
    defer { close(readEnd) }
    Thread {
      defer {
        close(writeEnd)
        finished.signal()
      }
      contents.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
          let written = write(writeEnd, buffer.baseAddress.map { $0 + offset }, min(buffer.count - offset, 7_000))
          guard written > 0 else {
            return
          }
          offset += written
        }
      }
    }.start()
    return try TarStreamExtractor.extract(
      from: FileDescriptorSource(readEnd), to: extracted, overrideModificationTime: overrideModificationTime)
  }

  /// Compares extracting `archive` with `bsdtar` against extracting `streamed`, which defaults to `archive`'s contents, in-process.
  private func expectParityWithBSDTar(_ archive: String, streaming streamed: Data? = nil) async throws {
    let expected = root.appendingPathComponent("bsdtar").path
    try fileManager.createDirectory(atPath: expected, withIntermediateDirectories: true)
    try await BSDTarExtractor().extract(.filePath(archive), to: expected, options: ArchiveExtractOptions(), logger: logger)
    let extracted = root.appendingPathComponent("inprocess").path

    let outcome = try extractFromPipe(try streamed ?? Data(contentsOf: URL(fileURLWithPath: archive)), to: extracted)

    let expectedTree = try tree(at: expected)
    let extractedTree = try tree(at: extracted)
    #expect(ArchiveFixtures.differences(expectedTree, extractedTree) == "")
    guard case .extracted(let summary, _) = outcome else {
      Issue.record("\(archive) was not read as a tar")
      return
    }
    #expect(summary.files == expectedTree.values.filter { $0.hasPrefix("file") }.count - 1, "a hard link is not a file written")
  }

  @Test(arguments: [
    ["-czf"],
    ["-cf"],
    ["--format", "gnutar", "-czf"],
    ["--format", "ustar", "-czf"],
  ])
  func extract_MatchesBSDTar(_ flags: [String]) async throws {
    let app = try makeApp()
    let archive = root.appendingPathComponent("a.tar").path
    if flags.contains("ustar") {
      // ustar cannot hold a name that long.
      try fileManager.removeItem(atPath: (app as NSString).appendingPathComponent("Real/nested-directory"))
    }
    try run("/usr/bin/tar", flags + [archive, "-C", root.path, "A.app"])
    try await expectParityWithBSDTar(archive)
  }

  @Test
  func extract_OfGzipMembersOneAfterAnother_MatchesBSDTar() async throws {
    _ = try makeApp()
    try run("/usr/bin/tar", ["-cf", "a.tar", "-C", root.path, "A.app"])
    // Splitting the tar partway through a file makes the second member start mid-entry.
    try run("/bin/sh", ["-c", "head -c 300000 a.tar | gzip > a.tgz && tail -c +300001 a.tar | gzip >> a.tgz"])

    try await expectParityWithBSDTar(root.appendingPathComponent("a.tgz").path)
  }

  @Test
  func extract_OfAZstdTar_MatchesBSDTarOfTheTar() async throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.tar")
    try run("/usr/bin/tar", ["-cf", archive.path, "-C", root.path, "A.app"])

    try await expectParityWithBSDTar(archive.path, streaming: ZstdFrame.stored(try Data(contentsOf: archive)))
  }

  @Test
  func extract_OfATruncatedZstd_Throws() throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.tar")
    try run("/usr/bin/tar", ["-cf", archive.path, "-C", root.path, "A.app"])
    let contents = ZstdFrame.stored(try Data(contentsOf: archive))

    #expect(throws: ArchiveError.corrupt("the zstd ends early")) {
      try extractFromPipe(contents.prefix(contents.count / 2), to: root.appendingPathComponent("extracted").path)
    }
  }

  @Test
  func extract_OfATruncatedGzip_Throws() throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.tgz").path
    try run("/usr/bin/tar", ["-czf", archive, "-C", root.path, "A.app"])
    let contents = try Data(contentsOf: URL(fileURLWithPath: archive))

    #expect(throws: ArchiveError.corrupt("the gzip ends early")) {
      try extractFromPipe(contents.prefix(contents.count / 2), to: root.appendingPathComponent("extracted").path)
    }
  }

  @Test
  func extract_RestoresExtendedAttributes() throws {
    let app = try makeApp()
    let archive = root.appendingPathComponent("a.tgz").path
    try run("/usr/bin/tar", ["-czf", archive, "-C", root.path, "A.app"])
    let extracted = root.appendingPathComponent("extracted").path

    _ = try extractFromPipe(try Data(contentsOf: URL(fileURLWithPath: archive)), to: extracted)

    var value = [UInt8](repeating: 0, count: 16)
    let count = getxattr("\(extracted)/A.app/Info.plist", "com.example.tag", &value, value.count, 0, 0)
    #expect(count >= 0 && String(decoding: value[..<max(count, 0)], as: UTF8.self) == "value")
    _ = app
  }

  /// macOS `tar` writes a file's `copyfile` metadata as an entry named `._<name>`
  /// before it, which `bsdtar` reads back and leaves out of its listing.
  @Test
  func extract_SkipsAppleDoubleEntries() throws {
    _ = try makeApp()
    try Data("metadata".utf8).write(to: root.appendingPathComponent("A.app/._Info.plist"))
    let archive = root.appendingPathComponent("a.tgz").path
    try run("/usr/bin/tar", ["-czf", archive, "-C", root.path, "A.app/._Info.plist", "A.app/Info.plist"])
    let extracted = root.appendingPathComponent("extracted").path

    _ = try extractFromPipe(try Data(contentsOf: URL(fileURLWithPath: archive)), to: extracted)

    #expect(!fileManager.fileExists(atPath: "\(extracted)/A.app/._Info.plist"))
    #expect(fileManager.fileExists(atPath: "\(extracted)/A.app/Info.plist"))
  }

  @Test
  func extract_WithOverrideModificationTime_StampsTheCurrentTime() throws {
    let app = try makeApp()
    try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: (app as NSString).appendingPathComponent("Info.plist"))
    let archive = root.appendingPathComponent("a.tgz").path
    try run("/usr/bin/tar", ["-czf", archive, "-C", root.path, "A.app"])
    let extracted = root.appendingPathComponent("extracted").path
    let before = Date().addingTimeInterval(-1)

    _ = try extractFromPipe(try Data(contentsOf: URL(fileURLWithPath: archive)), to: extracted, overrideModificationTime: true)

    let modified = try #require(try fileManager.attributesOfItem(atPath: "\(extracted)/A.app/Info.plist")[.modificationDate] as? Date)
    #expect(modified > before)
  }

  @Test
  func extract_RejectsAPathOutsideTheExtraction() throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.tar").path
    try run("/usr/bin/tar", ["-cf", archive, "-C", root.path, "-s", ",^A.app/Info.plist$,../escaped,", "A.app"])
    let extracted = root.appendingPathComponent("extracted").path

    #expect(throws: ArchiveError.unsafePath("../escaped")) {
      try extractFromPipe(try Data(contentsOf: URL(fileURLWithPath: archive)), to: extracted)
    }
    #expect(!fileManager.fileExists(atPath: root.appendingPathComponent("escaped").path))
  }

  @Test
  func extract_RefusesToWriteThroughASymlink() throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.tar").path
    // LinkDir, a symlink to Real, comes before a file renamed to be beneath it.
    try run("/usr/bin/tar", ["-cf", archive, "-C", root.path, "-s", ",^A.app/Private/key$,A.app/LinkDir/key,", "A.app/LinkDir", "A.app/Private/key"])
    let extracted = root.appendingPathComponent("extracted").path

    #expect(throws: POSIXError.self) {
      try extractFromPipe(try Data(contentsOf: URL(fileURLWithPath: archive)), to: extracted)
    }
    #expect(!fileManager.fileExists(atPath: "\(extracted)/A.app/Real/key"))
  }

  @Test
  func extract_OfSomethingElse_ReturnsEverythingItRead() throws {
    let app = try makeApp()
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive])
    let contents = try Data(contentsOf: URL(fileURLWithPath: archive))

    let outcome = try TarStreamExtractor.extract(from: DataSource(contents, pieceSize: 7_000), to: root.appendingPathComponent("extracted").path)

    guard case .notTar(let rest) = outcome else {
      Issue.record("a zip was read as a tar")
      return
    }
    var replayed = Data()
    var chunk = [UInt8](repeating: 0, count: 1 << 16)
    while case let count = try chunk.withUnsafeMutableBytes({ try rest.read(into: $0) }), count > 0 {
      replayed.append(contentsOf: chunk[..<count])
    }
    #expect(replayed == contents)
  }

  // MARK: - InProcessTarExtractor

  @Test(arguments: [false, true])
  func inProcessTarExtractor_ExtractsATarStreamOrPassesAnythingElseOn(_ zip: Bool) async throws {
    let app = try makeApp()
    let archive = root.appendingPathComponent(zip ? "a.ipa" : "a.tgz").path
    if zip {
      try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive])
    } else {
      try run("/usr/bin/tar", ["-czf", archive, "-C", root.path, "A.app"])
    }
    let expected = root.appendingPathComponent("bsdtar").path
    try fileManager.createDirectory(atPath: expected, withIntermediateDirectories: true)
    // Streamed, as a zip read without its central directory extracts differently.
    let stream = { FBProcessInput<NSData>(from: try Data(contentsOf: URL(fileURLWithPath: archive))).retyped(FBProcessInput<AnyObject>.self) }
    try await BSDTarExtractor().extract(.stream(try stream()), to: expected, options: ArchiveExtractOptions(), logger: logger)
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)

    try await InProcessTarExtractor(fallback: BSDTarExtractor()).extract(.stream(try stream()), to: extracted, options: ArchiveExtractOptions(), logger: logger)

    let expectedTree = try tree(at: expected)
    let extractedTree = try tree(at: extracted)
    #expect(extractedTree == expectedTree)
  }

  @Test
  func inProcessTarExtractor_WhenTheFallbackFailsBeforeReading_FailsWithItsError() async throws {
    let extracted = root.appendingPathComponent("extracted").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)
    let (outcomes, outcome) = AsyncStream<Result<Void, Error>>.makeStream()
    Task {
      do {
        let input = FBProcessInput<NSData>(from: Data(repeating: 0x41, count: 4096)).retyped(FBProcessInput<AnyObject>.self)
        try await InProcessTarExtractor(fallback: FailingBeforeReading()).extract(
          .stream(input), to: extracted, options: ArchiveExtractOptions(), logger: ControlCoreGlobalConfiguration.defaultLogger)
        outcome.yield(.success(()))
      } catch {
        outcome.yield(.failure(error))
      }
    }
    // Generous, as only a hang reaches it, and a full suite can keep the extraction waiting tens of seconds for a thread.
    Task {
      try? await Task.sleep(for: .seconds(120))
      outcome.finish()
    }

    let first = await outcomes.first { _ in true }

    #expect(throws: FailingBeforeReading.Failure.self) { try first?.get() }
  }

  private struct RefusingExtractor: ArchiveExtractor {
    func extract(_ source: ArchiveSource, to extractPath: String, options: ArchiveExtractOptions, logger: any ControlCoreLogger) async throws {
      throw ArchiveError.corrupt("passed on to the fallback")
    }

    func extract(from source: any ByteSource, to extractPath: String, options: ArchiveExtractOptions, logger: any ControlCoreLogger) async throws {
      throw ArchiveError.corrupt("passed on to the fallback")
    }
  }

  @Test
  func inProcessTarExtractor_ExtractsAZstdTarStreamWithoutItsFallback() async throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.tar")
    try run("/usr/bin/tar", ["-cf", archive.path, "-C", root.path, "A.app"])
    let expected = root.appendingPathComponent("bsdtar").path
    try fileManager.createDirectory(atPath: expected, withIntermediateDirectories: true)
    try await BSDTarExtractor().extract(.filePath(archive.path), to: expected, options: ArchiveExtractOptions(), logger: logger)
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)
    let stream = FBProcessInput<NSData>(from: ZstdFrame.stored(try Data(contentsOf: archive))).retyped(FBProcessInput<AnyObject>.self)

    try await InProcessTarExtractor(fallback: RefusingExtractor()).extract(.stream(stream), to: extracted, options: ArchiveExtractOptions(), logger: logger)

    #expect(try tree(at: extracted) == tree(at: expected))
  }
}

/// Fails without attaching its input, as a fallback cancelled before it starts does.
private struct FailingBeforeReading: ArchiveExtractor {

  struct Failure: Error, Equatable {}

  func extract(_ source: ArchiveSource, to extractPath: String, options: ArchiveExtractOptions, logger: any ControlCoreLogger) async throws {
    throw Failure()
  }

  func extract(from source: any ByteSource, to extractPath: String, options: ArchiveExtractOptions, logger: any ControlCoreLogger) async throws {
    throw Failure()
  }
}
