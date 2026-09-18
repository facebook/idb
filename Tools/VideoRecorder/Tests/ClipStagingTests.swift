/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import SimulatorVideo
import Testing

/// A file manager whose second move fails, after letting a test stand in for whatever else the
/// machine did in the window between the two.
private final class ReplacingFileManager: FileManager, @unchecked Sendable {
  var beforeFailingTheSecondMove: (() -> Void)?
  private var moves = 0

  override func moveItem(at source: URL, to destination: URL) throws {
    moves += 1
    guard moves > 1 else {
      try super.moveItem(at: source, to: destination)
      return
    }
    beforeFailingTheSecondMove?()
    throw CocoaError(.fileWriteFileExists)
  }
}

@Suite struct ClipStagingTests {
  private func scratch() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("idb-clip-staging-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  @Test func stagesTheClipAndItsReportSomewhereOfItsOwn() throws {
    let destination = try scratch().appendingPathComponent("demo.mp4")

    let staging = try ClipStaging(for: destination)
    defer { staging.discard() }

    #expect(staging.clip.lastPathComponent == "demo.mp4")
    #expect(staging.report.lastPathComponent == "demo.mp4.json")
    #expect(staging.clip.deletingLastPathComponent() == staging.directory)
    #expect(staging.directory != destination.deletingLastPathComponent())
    #expect(!FileManager.default.fileExists(atPath: destination.path))
  }

  @Test func publishesBothFilesWhereTheyWereAskedFor() throws {
    let destination = try scratch().appendingPathComponent("demo.mp4")
    let staging = try ClipStaging(for: destination)
    defer { staging.discard() }
    try "a clip".write(to: staging.clip, atomically: true, encoding: .utf8)
    try "a report".write(to: staging.report, atomically: true, encoding: .utf8)

    try staging.promote(to: destination)

    #expect(try String(contentsOf: destination, encoding: .utf8) == "a clip")
    #expect(
      try String(contentsOf: ClipStaging.reportURL(for: destination), encoding: .utf8)
        == "a report")
  }

  @Test func refusesToReplaceAClipThatAppearedWhileItWasCutting() throws {
    let destination = try scratch().appendingPathComponent("demo.mp4")
    let staging = try ClipStaging(for: destination)
    defer { staging.discard() }
    try "a clip".write(to: staging.clip, atomically: true, encoding: .utf8)
    try "a report".write(to: staging.report, atomically: true, encoding: .utf8)
    // Whoever wrote this after the refusal that checked for it owns it.
    try "someone else's".write(to: destination, atomically: true, encoding: .utf8)

    #expect(throws: (any Error).self) { try staging.promote(to: destination) }

    #expect(try String(contentsOf: destination, encoding: .utf8) == "someone else's")
    #expect(FileManager.default.fileExists(atPath: staging.clip.path))
  }

  @Test func leavesNoClipBehindWhenItsReportCannotBePublished() throws {
    let destination = try scratch().appendingPathComponent("demo.mp4")
    let staging = try ClipStaging(for: destination)
    defer { staging.discard() }
    try "a clip".write(to: staging.clip, atomically: true, encoding: .utf8)
    try "a report".write(to: staging.report, atomically: true, encoding: .utf8)
    try "someone else's".write(
      to: ClipStaging.reportURL(for: destination), atomically: true, encoding: .utf8)

    #expect(throws: (any Error).self) { try staging.promote(to: destination) }

    #expect(!FileManager.default.fileExists(atPath: destination.path))
    #expect(
      try String(contentsOf: ClipStaging.reportURL(for: destination), encoding: .utf8)
        == "someone else's")
  }

  @Test func leavesAClipSomeoneElseReplacedItWith() throws {
    let destination = try scratch().appendingPathComponent("demo.mp4")
    let fileManager = ReplacingFileManager()
    let staging = try ClipStaging(for: destination, using: fileManager)
    defer { staging.discard() }
    try "a clip".write(to: staging.clip, atomically: true, encoding: .utf8)
    try "a report".write(to: staging.report, atomically: true, encoding: .utf8)
    // Between publishing the clip and publishing its report, another publisher replaces it.
    fileManager.beforeFailingTheSecondMove = {
      try? FileManager.default.removeItem(at: destination)
      try? "someone else's".write(to: destination, atomically: true, encoding: .utf8)
    }

    #expect(throws: (any Error).self) { try staging.promote(to: destination, using: fileManager) }

    #expect(try String(contentsOf: destination, encoding: .utf8) == "someone else's")
  }

  @Test func removesEverythingItStaged() throws {
    let destination = try scratch().appendingPathComponent("demo.mp4")
    let staging = try ClipStaging(for: destination)
    try "a clip".write(to: staging.clip, atomically: true, encoding: .utf8)

    staging.discard()

    #expect(!FileManager.default.fileExists(atPath: staging.directory.path))
  }
}
