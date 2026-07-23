/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Testing

/// Tests that `ReplReportWriter` writes the report to disk, appends when a reconnect
/// reports the same session id, recreates it otherwise, and links artifacts stored
/// in the report's sibling directory.
@Suite
struct ReplReportWriterTests {

  private let epoch = Date(timeIntervalSince1970: 0)

  private static let simulatorMeta = SessionMeta(v: 1, context: "simulator", bundleID: nil, testBundlePath: nil, freshLaunch: nil)
  private static let appMeta = SessionMeta(v: 1, context: "app", bundleID: "x", testBundlePath: nil, freshLaunch: true)

  @Test
  func writesHeaderAndRunToFile() throws {
    let path = Self.tempReportPath()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let writer = ReplReportWriter(path: path)
    let resolved = writer.open(meta: Self.simulatorMeta, target: "sim 17.5", reason: "why", sessionID: "s1", startedAt: epoch)
    #expect(resolved == path)
    writer.recordRun(index: 0, code: "return 1", output: "Result:\n1", artifactFilenames: [], at: epoch)
    writer.close()

    let contents = try String(contentsOfFile: path, encoding: .utf8)
    #expect(contents.contains("<!-- idb-repl-session: s1 -->"))
    #expect(contents.contains("# idb-repl session report"))
    #expect(contents.contains("## Run 0"))
    #expect(contents.contains("return 1"))
    #expect(contents.contains("Result:\n1"))
  }

  @Test
  func differentSessionOverwritesExistingReport() throws {
    let path = Self.tempReportPath()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let first = ReplReportWriter(path: path)
    first.open(meta: Self.appMeta, target: "t", reason: nil, sessionID: "old", startedAt: epoch)
    first.recordRun(index: 0, code: "return \"first\"", output: "Result:\nfirst", artifactFilenames: [], at: epoch)
    first.close()

    // A new session id at the same path means a reset: the report is recreated.
    let second = ReplReportWriter(path: path)
    second.open(meta: Self.appMeta, target: "t", reason: nil, sessionID: "new", startedAt: epoch)
    second.recordRun(index: 0, code: "return \"second\"", output: "Result:\nsecond", artifactFilenames: [], at: epoch)
    second.close()

    let contents = try String(contentsOfFile: path, encoding: .utf8)
    #expect(contents.contains("<!-- idb-repl-session: new -->"))
    #expect(contents.contains("second"))
    #expect(!contents.contains("first"))
  }

  @Test
  func sameSessionAppendsToExistingReport() throws {
    let path = Self.tempReportPath()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let first = ReplReportWriter(path: path)
    first.open(meta: Self.appMeta, target: "t", reason: nil, sessionID: "same", startedAt: epoch)
    first.recordRun(index: 0, code: "return \"first\"", output: "Result:\nfirst", artifactFilenames: [], at: epoch)
    first.close()

    // Reconnecting with the same session id appends rather than overwriting.
    let second = ReplReportWriter(path: path)
    second.open(meta: Self.appMeta, target: "t", reason: nil, sessionID: "same", startedAt: epoch)
    second.recordRun(index: 1, code: "return \"second\"", output: "Result:\nsecond", artifactFilenames: [], at: epoch)
    second.close()

    let contents = try String(contentsOfFile: path, encoding: .utf8)
    #expect(contents.contains("first"))
    #expect(contents.contains("second"))
    #expect(contents.contains("Reconnected"))
    #expect(contents.contains("## Run 0"))
    #expect(contents.contains("## Run 1"))
    // The header (and its marker) is written once, not repeated on reconnect.
    let markerCount = contents.components(separatedBy: "<!-- idb-repl-session: same -->").count - 1
    #expect(markerCount == 1)
  }

  @Test
  func createsParentDirectories() throws {
    let base = Self.tempDir()
    let path = (base as NSString).appendingPathComponent("nested/report.md")
    defer { try? FileManager.default.removeItem(atPath: base) }

    let writer = ReplReportWriter(path: path)
    let resolved = writer.open(meta: Self.simulatorMeta, target: "t", reason: nil, sessionID: "s", startedAt: epoch)
    writer.close()
    #expect(resolved == path)
    #expect(FileManager.default.fileExists(atPath: path))
  }

  // MARK: - artifacts

  @Test
  func artifactsDirectoryIsNamedAfterReportBaseName() {
    let base = Self.tempDir()
    defer { try? FileManager.default.removeItem(atPath: base) }
    let path = (base as NSString).appendingPathComponent("report-123.md")

    let writer = ReplReportWriter(path: path)
    let directory = writer.artifactsDirectory()
    #expect(directory == (base as NSString).appendingPathComponent("report-123"))
    #expect(FileManager.default.fileExists(atPath: directory ?? ""))
  }

  @Test
  func recordRunLinksArtifactsBesideReport() throws {
    let base = Self.tempDir()
    defer { try? FileManager.default.removeItem(atPath: base) }
    let path = (base as NSString).appendingPathComponent("session.md")

    let writer = ReplReportWriter(path: path)
    writer.open(meta: Self.appMeta, target: "t", reason: nil, sessionID: "s", startedAt: epoch)
    // Simulate an artifact transferred into the report's artifacts directory.
    let directory = try #require(writer.artifactsDirectory())
    let artifact = (directory as NSString).appendingPathComponent("screenshot_0_1.png")
    FileManager.default.createFile(atPath: artifact, contents: Data([0x89]))
    writer.recordRun(index: 0, code: "IDB.screenshot.save()", output: "Result:\nok", artifactFilenames: ["screenshot_0_1.png"], at: epoch)
    writer.close()

    let contents = try String(contentsOfFile: path, encoding: .utf8)
    #expect(contents.contains("**Artifacts**"))
    #expect(contents.contains("![screenshot_0_1.png](session/screenshot_0_1.png)"))
    #expect(FileManager.default.fileExists(atPath: artifact))
  }

  @Test
  func freshReportClearsStaleArtifactsFromAPriorSession() throws {
    let base = Self.tempDir()
    defer { try? FileManager.default.removeItem(atPath: base) }
    let path = (base as NSString).appendingPathComponent("session.md")

    let first = ReplReportWriter(path: path)
    first.open(meta: Self.appMeta, target: "t", reason: nil, sessionID: "old", startedAt: epoch)
    let directory = try #require(first.artifactsDirectory())
    let staleArtifact = (directory as NSString).appendingPathComponent("screenshot_0_1.png")
    FileManager.default.createFile(atPath: staleArtifact, contents: Data([0x89]))
    first.close()

    // A fresh session at the same path drops the previous session's artifacts.
    let second = ReplReportWriter(path: path)
    second.open(meta: Self.appMeta, target: "t", reason: nil, sessionID: "new", startedAt: epoch)
    second.close()
    #expect(!FileManager.default.fileExists(atPath: staleArtifact))
  }

  private static func tempReportPath() -> String {
    (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("idb_repl_report_test_\(UUID().uuidString).md")
  }

  private static func tempDir() -> String {
    (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("idb_repl_report_test_\(UUID().uuidString)")
  }
}
