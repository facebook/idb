/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Writes a Markdown session report incrementally as the REPL runs. The report
/// path is user-supplied; the file is overwritten when opened, and each recorded
/// run is written and flushed immediately, so a crash mid-session still leaves a
/// valid partial report.
///
/// All I/O is best-effort: the first failure is reported once on stderr and then
/// writing is disabled, so a bad path or a full disk never interrupts the REPL.
final class ReplReportWriter {

  private let path: String
  private var handle: FileHandle?
  private var disabled = false

  /// `path` may start with `~`; it is expanded here.
  init(path: String) {
    self.path = (path as NSString).expandingTildeInPath
  }

  /// Creates the report file (truncating any existing file) and writes its header.
  /// Returns the resolved path on success, or nil if the report could not be
  /// created — in which case nothing is written and the caller should discard this
  /// writer.
  @discardableResult
  func open(context: String, target: String, reason: String?, startedAt: Date) -> String? {
    let directory = (path as NSString).deletingLastPathComponent
    if !directory.isEmpty {
      try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }
    guard FileManager.default.createFile(atPath: path, contents: nil),
      let handle = FileHandle(forWritingAtPath: path)
    else {
      FileHandle.standardError.write(Data("idb-repl: could not open session report at \(path); reporting disabled\n".utf8))
      return nil
    }
    self.handle = handle
    write(ReplReportFormatter.header(context: context, target: target, reason: reason, startedAt: startedAt))
    return path
  }

  /// Records a completed run — a value or a runtime exception.
  func recordRun(index: Int, code: String, output: String, at date: Date) {
    write(ReplReportFormatter.runEntry(index: index, code: code, output: output, at: date))
  }

  /// Records a run whose code failed to compile (only reached under `--report-failures`).
  func recordCompileFailure(index: Int, code: String, compilerOutput: String, at date: Date) {
    write(ReplReportFormatter.compileFailureEntry(index: index, code: code, compilerOutput: compilerOutput, at: date))
  }

  /// Closes the report file. Further writes are no-ops.
  func close() {
    try? handle?.close()
    handle = nil
  }

  // MARK: - Private

  /// Appends `text` to the report, disabling reporting on the first failure.
  private func write(_ text: String) {
    guard !disabled, let handle else {
      return
    }
    do {
      try handle.write(contentsOf: Data(text.utf8))
    } catch {
      disabled = true
      FileHandle.standardError.write(Data("idb-repl: failed writing session report (\(error)); reporting disabled\n".utf8))
    }
  }
}
