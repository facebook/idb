/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Writes a Markdown session report incrementally as the REPL runs. Reconnecting to
/// a still-running app session (same session id) appends to the existing report at
/// the given path; otherwise the report is created fresh. Each recorded run is
/// written and flushed immediately, so a crash mid-session still leaves a valid
/// partial report.
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

  /// Opens the report and returns its resolved path, or nil if it could not be
  /// created (in which case nothing is written and the caller should discard this
  /// writer).
  ///
  /// When a report for the same `sessionID` already exists at `path` — a reconnect
  /// to a still-running app session — its runs are appended after a reconnect
  /// marker; if that existing report cannot be opened or seeked, reporting is
  /// disabled (returns nil) rather than truncating it. Otherwise the file is
  /// created fresh (truncating any unrelated existing file), starting with the
  /// session marker and header.
  @discardableResult
  func open(context: String, target: String, reason: String?, sessionID: String, startedAt: Date) -> String? {
    let directory = (path as NSString).deletingLastPathComponent
    if !directory.isEmpty {
      try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    // Resume an existing report only when it belongs to this same REPL session.
    // This is a reconnect, so the existing report must be appended to, never
    // truncated: if it cannot be opened or seeked to the end, disable reporting
    // (return nil) rather than falling through and recreating it. Failures here are
    // reported on stderr but never interrupt the session (I/O is best-effort).
    if !sessionID.isEmpty, Self.existingSessionID(atPath: path) == sessionID {
      guard let handle = FileHandle(forWritingAtPath: path) else {
        FileHandle.standardError.write(Data("idb-repl: could not open session report at \(path) to append; reporting disabled\n".utf8))
        return nil
      }
      do {
        try handle.seekToEnd()
      } catch {
        try? handle.close()
        FileHandle.standardError.write(Data("idb-repl: could not seek session report at \(path) (\(error)); reporting disabled\n".utf8))
        return nil
      }
      self.handle = handle
      write(ReplReportFormatter.reconnectMarker(at: startedAt))
      return path
    }

    guard FileManager.default.createFile(atPath: path, contents: nil),
      let handle = FileHandle(forWritingAtPath: path)
    else {
      FileHandle.standardError.write(Data("idb-repl: could not open session report at \(path); reporting disabled\n".utf8))
      return nil
    }
    self.handle = handle
    write(ReplReportFormatter.header(context: context, target: target, reason: reason, sessionID: sessionID, startedAt: startedAt))
    return path
  }

  /// Records a completed run — a value or a runtime exception.
  func recordRun(index: Int, code: String, output: String, at date: Date) {
    write(ReplReportFormatter.runEntry(index: index, code: code, output: output, at: date))
  }

  /// Records a run whose code failed to compile (only reached under `--report-failures`).
  func recordCompileFailure(code: String, compilerOutput: String, at date: Date) {
    write(ReplReportFormatter.compileFailureEntry(code: code, compilerOutput: compilerOutput, at: date))
  }

  /// Closes the report file. Further writes are no-ops.
  func close() {
    try? handle?.close()
    handle = nil
  }

  // MARK: - Private

  /// The session id recorded in the report at `path` (its marker line), or nil when
  /// there is no readable report or it has no marker.
  private static func existingSessionID(atPath path: String) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else {
      return nil
    }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 4096),
      let text = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    let firstLine = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
    return ReplReportFormatter.sessionID(fromHeaderLine: firstLine)
  }

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
