/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Structured, machine-readable session metadata embedded in a report's header as a
/// hidden marker. Records what `replay` needs to reconstruct the session: the context
/// kind and, per kind, the bundle/path it targeted and (for `app`) whether the app was
/// freshly launched. `v` is a schema version for forward-compatibility.
struct SessionMeta: Codable, Equatable {
  var v: Int
  var context: String
  var bundleID: String?
  var testBundlePath: String?
  var freshLaunch: Bool?

  /// The human-readable label shown in the report's `- **Context:**` line, derived from
  /// the structured fields so the visible label and the marker cannot drift.
  var reportLabel: String {
    switch context {
    case "app": return "app (`\(bundleID ?? "")`)"
    case "test": return "test (`\(testBundlePath ?? "")`)"
    default: return context
    }
  }
}

/// Structured, machine-readable metadata for a single run, embedded as a hidden marker
/// immediately before the run's section. `at` is the run's epoch time with sub-second
/// precision (the canonical timestamp for `--realtime`, finer than the 1-second visible
/// heading); `status` is `ok` for a completed run (including a runtime exception) or
/// `compile-failed` for a run whose code did not compile.
struct RunMeta: Codable, Equatable {
  var index: Int
  var at: Double
  var status: String

  static let statusOK = "ok"
  static let statusCompileFailed = "compile-failed"
}

/// Pure Markdown formatting for `idb-repl` session reports. Every function returns
/// a string and performs no I/O, so the report's shape can be unit-tested directly;
/// the file handling lives in `ReplReportWriter`.
///
/// Each report also carries hidden, machine-readable markers (HTML comments, invisible
/// in rendered Markdown) that `ReplReportParser` reads back to replay the session: an
/// `idb-repl-meta` marker in the header and an `idb-repl-run` marker before each run.
enum ReplReportFormatter {

  /// The report's leading header: the machine-readable session and metadata markers,
  /// then a title and a metadata list, written when a report is first created. Ends with
  /// a horizontal rule so the first run reads as a new section.
  static func header(meta: SessionMeta, target: String, reason: String?, sessionID: String, startedAt: Date) -> String {
    var lines = [
      sessionMarker(sessionID),
      sessionMetaMarker(meta),
      "# idb-repl session report",
      "",
      "- **Context:** \(meta.reportLabel)",
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

  /// The hidden session-metadata marker line, `<!-- idb-repl-meta: {json} -->`.
  static func sessionMetaMarker(_ meta: SessionMeta) -> String {
    marker(prefix: sessionMetaMarkerPrefix, value: meta)
  }

  /// The session metadata parsed from a report line, or nil when `line` is not a
  /// session-metadata marker or its JSON does not decode.
  static func sessionMeta(fromLine line: String) -> SessionMeta? {
    decodeMarker(line, prefix: sessionMetaMarkerPrefix)
  }

  /// The hidden per-run marker line, `<!-- idb-repl-run: {json} -->`.
  static func runMarker(_ meta: RunMeta) -> String {
    marker(prefix: runMarkerPrefix, value: meta)
  }

  /// The run metadata parsed from a report line, or nil when `line` is not a run marker
  /// or its JSON does not decode.
  static func runMeta(fromLine line: String) -> RunMeta? {
    decodeMarker(line, prefix: runMarkerPrefix)
  }

  /// A marker appended when a run resumes an existing report — a reconnect to a
  /// still-running app session.
  static func reconnectMarker(at date: Date) -> String {
    "\n_Reconnected \(timestamp(date))_\n"
  }

  /// A single completed run: a hidden run marker, then its number and time, the user's
  /// code, the output the target returned (already prefixed `Result:` or `Exception:`),
  /// and links to any artifacts captured during the run. A runtime exception is still a
  /// completed run — the code compiled and executed.
  static func runEntry(index: Int, code: String, output: String, artifacts: [String], at date: Date) -> String {
    var entry = "\n" + runMarker(RunMeta(index: index, at: date.timeIntervalSince1970, status: RunMeta.statusOK))
    entry += section(
      heading: "Run \(index) — \(timestamp(date))",
      code: code,
      bodyLabel: "Output",
      body: output)
    if !artifacts.isEmpty {
      entry += artifactsBlock(artifacts)
    }
    return entry
  }

  /// A run whose code failed to compile, recorded only under `--report-failures`: a
  /// hidden run marker flagged `compile-failed`, then the user's code and the compiler
  /// diagnostics.
  static func compileFailureEntry(index: Int, code: String, compilerOutput: String, at date: Date) -> String {
    var entry = "\n" + runMarker(RunMeta(index: index, at: date.timeIntervalSince1970, status: RunMeta.statusCompileFailed))
    entry += section(
      heading: "Failed Run — \(timestamp(date))",
      code: code,
      bodyLabel: "Compile error",
      body: compilerOutput)
    return entry
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

  /// Builds a hidden HTML-comment marker line carrying `value` as JSON.
  private static func marker<T: Encodable>(prefix: String, value: T) -> String {
    let json = (try? jsonEncoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return "\(prefix)\(json)\(markerSuffix)"
  }

  /// Decodes a `T` from a marker line beginning with `prefix`, or nil when the line is
  /// not that marker or its JSON does not decode.
  private static func decodeMarker<T: Decodable>(_ line: String, prefix: String) -> T? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(markerSuffix),
      trimmed.count >= prefix.count + markerSuffix.count
    else {
      return nil
    }
    let start = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
    let end = trimmed.index(trimmed.endIndex, offsetBy: -markerSuffix.count)
    let json = String(trimmed[start..<end])
    return json.data(using: .utf8).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
  }

  private static let sessionMarkerPrefix = "<!-- idb-repl-session: "
  private static let sessionMarkerSuffix = " -->"
  private static let sessionMetaMarkerPrefix = "<!-- idb-repl-meta: "
  private static let runMarkerPrefix = "<!-- idb-repl-run: "
  private static let markerSuffix = " -->"

  private static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    // Sorted keys make the marker deterministic (stable across runs and testable).
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

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
