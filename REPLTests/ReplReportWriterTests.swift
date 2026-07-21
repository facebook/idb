/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Testing

/// Tests that `ReplReportWriter` writes the report to disk and overwrites an
/// existing file when opened.
@Suite
struct ReplReportWriterTests {

  private let epoch = Date(timeIntervalSince1970: 0)

  @Test
  func writesHeaderAndRunToFile() throws {
    let path = Self.tempReportPath()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let writer = ReplReportWriter(path: path)
    let resolved = writer.open(context: "simulator", target: "sim 17.5", reason: "why", startedAt: epoch)
    #expect(resolved == path)
    writer.recordRun(index: 0, code: "return 1", output: "Result:\n1", at: epoch)
    writer.close()

    let contents = try String(contentsOfFile: path, encoding: .utf8)
    #expect(contents.contains("# idb-repl session report"))
    #expect(contents.contains("- **Context:** simulator"))
    #expect(contents.contains("## Run 0"))
    #expect(contents.contains("return 1"))
    #expect(contents.contains("Result:\n1"))
  }

  @Test
  func openOverwritesExistingFile() throws {
    let path = Self.tempReportPath()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let first = ReplReportWriter(path: path)
    first.open(context: "simulator", target: "t", reason: nil, startedAt: epoch)
    first.recordRun(index: 0, code: "return \"first\"", output: "Result:\nfirst", at: epoch)
    first.close()

    let second = ReplReportWriter(path: path)
    second.open(context: "simulator", target: "t", reason: nil, startedAt: epoch)
    second.recordRun(index: 0, code: "return \"second\"", output: "Result:\nsecond", at: epoch)
    second.close()

    let contents = try String(contentsOfFile: path, encoding: .utf8)
    #expect(contents.contains("second"))
    #expect(!contents.contains("first"))
  }

  @Test
  func createsParentDirectories() throws {
    let base = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("idb_repl_report_test_\(UUID().uuidString)")
    let path = (base as NSString).appendingPathComponent("nested/report.md")
    defer { try? FileManager.default.removeItem(atPath: base) }

    let writer = ReplReportWriter(path: path)
    let resolved = writer.open(context: "simulator", target: "t", reason: nil, startedAt: epoch)
    writer.close()
    #expect(resolved == path)
    #expect(FileManager.default.fileExists(atPath: path))
  }

  private static func tempReportPath() -> String {
    (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("idb_repl_report_test_\(UUID().uuidString).md")
  }
}
