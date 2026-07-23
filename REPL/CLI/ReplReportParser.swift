/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The session reconstructed from a report, ready to replay: the context to start and
/// the replayable runs in order. Runs whose code failed to compile are excluded (they
/// would only fail again) but counted in `skippedFailedRuns` so the caller can report
/// how many were skipped.
struct ParsedReplaySession: Equatable {
  var context: ParsedContext
  var runs: [ParsedRun]
  var skippedFailedRuns: Int
}

/// The context a report was recorded in, parsed from its session-metadata marker. Carries
/// the parameters replay needs to reconstruct the session; `freshLaunch` records whether
/// the app was freshly launched at the original session's start.
enum ParsedContext: Equatable {
  case simulator
  case test(bundlePath: String)
  case app(bundleID: String, freshLaunch: Bool)
}

/// A single replayable run: its original index (informational), the Swift code to run,
/// and the time it completed in the original session (used to pace `--realtime`).
struct ParsedRun: Equatable {
  var index: Int
  var code: String
  var timestamp: Date
}

/// A failure while parsing a session report for replay. Its description is shown to the
/// user.
enum ReplReportParseError: Error, CustomStringConvertible {
  case missingSessionMeta
  case unknownContext(String)
  case missingBundleID
  case missingTestBundlePath

  var description: String {
    switch self {
    case .missingSessionMeta:
      return "The report has no idb-repl session metadata; it was not produced by --report-path or is corrupt."
    case let .unknownContext(context):
      return "The report records an unknown session context '\(context)'."
    case .missingBundleID:
      return "The report records an app session but no bundle id."
    case .missingTestBundlePath:
      return "The report records a test session but no test bundle path."
    }
  }
}

/// Parses an `idb-repl` session report into a replayable session by reading the hidden,
/// machine-readable markers that `ReplReportFormatter` embeds — never by scraping the
/// human-readable Markdown. Pure and free of I/O, so it can be unit-tested directly.
enum ReplReportParser {

  static func parse(_ markdown: String) throws -> ParsedReplaySession {
    var sessionMeta: SessionMeta?
    var runs: [ParsedRun] = []
    var skippedFailedRuns = 0

    // Fence state: markers are only recognized outside a fenced code block, so a line
    // inside user code that looks like a marker or heading is never mistaken for report
    // structure. A fence closes on a line of exactly `fenceLength` backticks, which the
    // formatter guarantees is longer than any backtick run inside the code.
    var insideFence = false
    var fenceLength = 0
    var capturingCode = false
    var codeLines: [String] = []
    // The run marker seen most recently, awaiting its Swift code block.
    var pendingRun: RunMeta?

    for line in markdown.components(separatedBy: "\n") {
      if insideFence {
        if let fence = Self.fenceInfo(line), fence.language.isEmpty, fence.length == fenceLength {
          insideFence = false
          if capturingCode, let meta = pendingRun {
            Self.commitRun(meta, code: codeLines.joined(separator: "\n"), into: &runs, skipped: &skippedFailedRuns)
            pendingRun = nil
            capturingCode = false
            codeLines = []
          }
        } else if capturingCode {
          codeLines.append(line)
        }
        continue
      }

      if sessionMeta == nil, let meta = ReplReportFormatter.sessionMeta(fromLine: line) {
        sessionMeta = meta
        continue
      }
      if let runMeta = ReplReportFormatter.runMeta(fromLine: line) {
        // A new run marker supersedes any prior one still awaiting code (malformed run).
        pendingRun = runMeta
        capturingCode = false
        codeLines = []
        continue
      }
      if let fence = Self.fenceInfo(line) {
        insideFence = true
        fenceLength = fence.length
        // Capture only the first Swift block after a run marker — its code. The Output
        // block that follows (a plain fence) is regenerated on replay, so it is skipped.
        capturingCode = (pendingRun != nil && fence.language == "swift")
        if capturingCode {
          codeLines = []
        }
      }
    }

    guard let sessionMeta else {
      throw ReplReportParseError.missingSessionMeta
    }
    return ParsedReplaySession(
      context: try Self.context(from: sessionMeta),
      runs: runs,
      skippedFailedRuns: skippedFailedRuns)
  }

  // MARK: - Private

  /// Records a parsed run: a completed run becomes replayable; a compile failure (or any
  /// non-`ok` status) is counted as skipped instead.
  private static func commitRun(_ meta: RunMeta, code: String, into runs: inout [ParsedRun], skipped: inout Int) {
    guard meta.status == RunMeta.statusOK else {
      skipped += 1
      return
    }
    runs.append(ParsedRun(index: meta.index, code: code, timestamp: Date(timeIntervalSince1970: meta.at)))
  }

  /// Maps the report's session metadata to the context to start, throwing when the
  /// context is unknown or a required parameter is absent.
  private static func context(from meta: SessionMeta) throws -> ParsedContext {
    switch meta.context {
    case "simulator":
      return .simulator
    case "test":
      guard let bundlePath = meta.testBundlePath, !bundlePath.isEmpty else {
        throw ReplReportParseError.missingTestBundlePath
      }
      return .test(bundlePath: bundlePath)
    case "app":
      guard let bundleID = meta.bundleID, !bundleID.isEmpty else {
        throw ReplReportParseError.missingBundleID
      }
      return .app(bundleID: bundleID, freshLaunch: meta.freshLaunch ?? false)
    default:
      throw ReplReportParseError.unknownContext(meta.context)
    }
  }

  /// Parses a Markdown fence line — a run of three or more leading backticks followed by
  /// an optional info string (a language, or empty for a closing/plain fence) — returning
  /// its backtick count and language, or nil when `line` is not a fence line. A line that
  /// contains further backticks after the leading run (e.g. inline code) is not a fence.
  private static func fenceInfo(_ line: String) -> (length: Int, language: String)? {
    var length = 0
    for character in line {
      if character == "`" {
        length += 1
      } else {
        break
      }
    }
    guard length >= 3 else {
      return nil
    }
    let rest = String(line.dropFirst(length))
    guard !rest.contains("`") else {
      return nil
    }
    return (length, rest.trimmingCharacters(in: .whitespaces))
  }
}
