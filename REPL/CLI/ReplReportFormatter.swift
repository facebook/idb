/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Pure Markdown formatting for `idb-repl` session reports. Every function returns
/// a string and performs no I/O, so the report's shape can be unit-tested directly;
/// the file handling lives in `ReplReportWriter`.
enum ReplReportFormatter {

  /// The report's leading header: a machine-readable session marker, then a title
  /// and a metadata list, written when a report is first created. Ends with a
  /// horizontal rule so the first run reads as a new section.
  static func header(context: String, target: String, reason: String?, sessionID: String, startedAt: Date) -> String {
    var lines = [
      sessionMarker(sessionID),
      "# idb-repl session report",
      "",
      "- **Context:** \(context)",
      "- **Target:** \(target)",
      "- **Started:** \(timestamp(startedAt))",
    ]
    if let reason, !reason.isEmpty {
      lines.append("- **Reason:** \(reason)")
    }
    lines.append(contentsOf: ["", "---", ""])
    return lines.joined(separator: "\n")
  }

  /// The report's first line: a machine-readable marker recording the REPL session
  /// the report belongs to. It is an HTML comment, so it is invisible in rendered
  /// Markdown; `ReplReportWriter` reads it back to decide whether a reconnect should
  /// append to an existing report or start a fresh one.
  static func sessionMarker(_ id: String) -> String {
    "\(sessionMarkerPrefix)\(id)\(sessionMarkerSuffix)"
  }

  /// Parses the session id from a report's first line, or nil when `line` is not a
  /// session marker.
  static func sessionID(fromHeaderLine line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix(sessionMarkerPrefix), trimmed.hasSuffix(sessionMarkerSuffix),
      trimmed.count >= sessionMarkerPrefix.count + sessionMarkerSuffix.count
    else {
      return nil
    }
    let start = trimmed.index(trimmed.startIndex, offsetBy: sessionMarkerPrefix.count)
    let end = trimmed.index(trimmed.endIndex, offsetBy: -sessionMarkerSuffix.count)
    return String(trimmed[start..<end])
  }

  /// A marker appended when a run resumes an existing report — a reconnect to a
  /// still-running app session.
  static func reconnectMarker(at date: Date) -> String {
    "\n_Reconnected \(timestamp(date))_\n"
  }

  /// A single completed run: its number and time, the user's code, and the output
  /// the target returned (already prefixed `Result:` or `Exception:`). A runtime
  /// exception is still a completed run — the code compiled and executed.
  static func runEntry(index: Int, code: String, output: String, at date: Date) -> String {
    section(
      heading: "Run \(index) — \(timestamp(date))",
      code: code,
      bodyLabel: "Output",
      body: output)
  }

  /// A run whose code failed to compile, recorded only under `--report-failures`:
  /// the user's code and the compiler diagnostics.
  static func compileFailureEntry(code: String, compilerOutput: String, at date: Date) -> String {
    section(
      heading: "Failed Run — \(timestamp(date))",
      code: code,
      bodyLabel: "Compile error",
      body: compilerOutput)
  }

  // MARK: - Private

  /// One run section: a leading blank line (separating it from the previous block),
  /// an H2 heading, the Swift code block, then a labeled body block.
  private static func section(heading: String, code: String, bodyLabel: String, body: String) -> String {
    [
      "",
      "## \(heading)",
      "",
      codeBlock(code, language: "swift"),
      "",
      "**\(bodyLabel)**",
      "",
      codeBlock(body),
      "",
    ].joined(separator: "\n")
  }

  /// Wraps `content` in a fenced code block whose fence is always longer than the
  /// longest backtick run inside `content`, so code that itself contains a ``` fence
  /// cannot break out of the block.
  private static func codeBlock(_ content: String, language: String = "") -> String {
    let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: content) + 1))
    return "\(fence)\(language)\n\(content)\n\(fence)"
  }

  /// The length of the longest run of consecutive backticks in `string`.
  private static func longestBacktickRun(in string: String) -> Int {
    var longest = 0
    var current = 0
    for character in string {
      if character == "`" {
        current += 1
        longest = max(longest, current)
      } else {
        current = 0
      }
    }
    return longest
  }

  private static let sessionMarkerPrefix = "<!-- idb-repl-session: "
  private static let sessionMarkerSuffix = " -->"

  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    return formatter
  }()

  private static func timestamp(_ date: Date) -> String {
    timestampFormatter.string(from: date)
  }
}
