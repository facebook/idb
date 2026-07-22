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

  /// A single completed run: its number and time, the user's code, the output the
  /// target returned (already prefixed `Result:` or `Exception:`), and links to any
  /// artifacts captured during the run. A runtime exception is still a completed run
  /// — the code compiled and executed.
  static func runEntry(index: Int, code: String, output: String, artifacts: [String], at date: Date) -> String {
    var entry = section(
      heading: "Run \(index) — \(timestamp(date))",
      code: code,
      bodyLabel: "Output",
      body: output)
    if !artifacts.isEmpty {
      entry += artifactsBlock(artifacts)
    }
    return entry
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

  /// The trailing "Artifacts" block for a run: each captured artifact as a
  /// report-relative Markdown reference. Images are embedded so they render inline;
  /// other files (e.g. video) are linked.
  private static func artifactsBlock(_ artifacts: [String]) -> String {
    var lines = ["", "**Artifacts**", ""]
    lines.append(contentsOf: artifacts.map(artifactReference))
    lines.append("")
    return lines.joined(separator: "\n")
  }

  /// A Markdown reference for a report-relative artifact path: `![name](path)` for
  /// images so they render inline, `[name](path)` for everything else.
  private static func artifactReference(_ path: String) -> String {
    let name = (path as NSString).lastPathComponent
    return isImagePath(path) ? "![\(name)](\(path))" : "[\(name)](\(path))"
  }

  /// Whether `path` names an image, by file extension.
  private static func isImagePath(_ path: String) -> Bool {
    let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]
    return imageExtensions.contains((path as NSString).pathExtension.lowercased())
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
