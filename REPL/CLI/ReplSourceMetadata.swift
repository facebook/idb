/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// Derives metrics metadata about user-entered REPL Swift. This is separate from
/// `ReplSourceGenerator`, which turns that code into a compilable source file;
/// nothing here contributes to compilation. Every function is pure and total, so
/// it can be unit-tested directly and never disrupts a REPL session.
enum ReplSourceMetadata {

  /// Estimates the number of *significant* lines of Swift code in `code`, for
  /// metrics. A line is delimited by a newline or a semicolon; delimiters that
  /// fall inside a string literal or a comment do not split a line, and lines
  /// that are blank or contain only a comment are not counted.
  ///
  /// This is a deliberately total, best-effort heuristic, not a real Swift
  /// parser: it performs no operation that can trap (no force-unwraps, no
  /// unchecked indexing, nothing that throws) and returns `0` for empty or
  /// otherwise insignificant input. A garbled snippet therefore yields at worst
  /// an imperfect count, never a crash, so metrics can never halt the REPL.
  ///
  /// Recognized string forms are regular (`"…"`), multiline (`"""…"""`), and raw
  /// (`#"…"#`, any number of `#`) literals; recognized comments are line
  /// (`//…`) and nestable block (`/* … */`) comments.
  static func countSignificantLinesOfCode(in code: String) -> Int {
    if code.isEmpty {
      return 0
    }

    let chars = Array(code)
    let n = chars.count

    var count = 0
    var currentLineHasCode = false
    var context = ScanContext.code

    // Finalize the logical line that just ended, counting it if it held code.
    func endLine() {
      if currentLineHasCode {
        count += 1
      }
      currentLineHasCode = false
    }

    var i = 0
    while i < n {
      let c = chars[i]

      switch context {
      case .code:
        if c == "/", i + 1 < n, chars[i + 1] == "/" {
          context = .lineComment
          i += 2
          continue
        }
        if c == "/", i + 1 < n, chars[i + 1] == "*" {
          context = .blockComment(depth: 1)
          i += 2
          continue
        }
        // A string opener: an optional run of `#` (the raw-string delimiter)
        // immediately followed by a quote.
        if c == "#" || c == "\"" {
          var pounds = 0
          var j = i
          while j < n, chars[j] == "#" {
            pounds += 1
            j += 1
          }
          if j < n, chars[j] == "\"" {
            let isMultiline =
              j + 2 < n && chars[j + 1] == "\"" && chars[j + 2] == "\""
            currentLineHasCode = true
            context = .stringLiteral(multiline: isMultiline, pounds: pounds)
            i = isMultiline ? j + 3 : j + 1
            continue
          }
          // Not a string opener (e.g. `#if`, `#selector`): ordinary code.
          currentLineHasCode = true
          i += 1
          continue
        }
        if c.isNewline || c == ";" {
          endLine()
          i += 1
          continue
        }
        if !c.isWhitespace {
          currentLineHasCode = true
        }
        i += 1

      case .lineComment:
        if c.isNewline {
          context = .code
          endLine()
        }
        i += 1

      case .blockComment(let depth):
        if c == "/", i + 1 < n, chars[i + 1] == "*" {
          context = .blockComment(depth: depth + 1)
          i += 2
          continue
        }
        if c == "*", i + 1 < n, chars[i + 1] == "/" {
          context = depth <= 1 ? .code : .blockComment(depth: depth - 1)
          i += 2
          continue
        }
        i += 1

      case .stringLiteral(let multiline, let pounds):
        // An escape is a backslash followed by exactly `pounds` `#`s (zero for a
        // non-raw string). It hides the next character, including a quote, so it
        // cannot end the string.
        if c == "\\" {
          var seenPounds = 0
          var j = i + 1
          while j < n, seenPounds < pounds, chars[j] == "#" {
            seenPounds += 1
            j += 1
          }
          if seenPounds == pounds {
            i = j + 1
            continue
          }
          i += 1
          continue
        }
        // The closing delimiter: one quote (three when multiline) followed by
        // `pounds` `#`s.
        if c == "\"" {
          let quotesNeeded = multiline ? 3 : 1
          var quotes = 0
          var j = i
          while j < n, quotes < quotesNeeded, chars[j] == "\"" {
            quotes += 1
            j += 1
          }
          if quotes == quotesNeeded {
            var seenPounds = 0
            var k = j
            while k < n, seenPounds < pounds, chars[k] == "#" {
              seenPounds += 1
              k += 1
            }
            if seenPounds == pounds {
              context = .code
              i = k
              continue
            }
          }
          i += 1
          continue
        }
        i += 1
      }
    }

    // Finalize a trailing line that had no delimiter.
    endLine()

    return max(0, count)
  }

  // MARK: - Private

  /// The scanning context of `countSignificantLinesOfCode(in:)`. Line delimiters
  /// split a line only in `.code`; inside comments and string literals they are
  /// literal content.
  private enum ScanContext {
    case code
    case lineComment
    case blockComment(depth: Int)
    case stringLiteral(multiline: Bool, pounds: Int)
  }
}
