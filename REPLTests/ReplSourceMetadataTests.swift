/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Testing

/// Tests the significant-line-of-code counter used for REPL metrics.
@Suite
struct ReplSourceMetadataTests {

  // MARK: - countSignificantLinesOfCode

  @Test
  func emptyAndWhitespaceOnlyCodeIsZero() {
    #expect(significantLines("") == 0)
    #expect(significantLines("   ") == 0)
    #expect(significantLines("\n\n\n") == 0)
    #expect(significantLines("  \n\t \n ") == 0)
  }

  @Test
  func singleStatementIsOneLine() {
    #expect(significantLines("let x = 1") == 1)
    // A trailing newline does not add an empty line.
    #expect(significantLines("let x = 1\n") == 1)
  }

  @Test
  func newlineSeparatedStatementsAreCounted() {
    #expect(significantLines("let x = 1\nlet y = 2\nlet z = 3") == 3)
  }

  @Test
  func blankLinesAreNotCounted() {
    #expect(significantLines("let x = 1\n\n\nlet y = 2") == 2)
  }

  @Test
  func semicolonsSeparateStatements() {
    #expect(significantLines("let x = 1; let y = 2") == 2)
    #expect(significantLines("foo(); bar(); baz()") == 3)
    // A trailing semicolon does not add an empty statement.
    #expect(significantLines("let x = 1;") == 1)
  }

  @Test
  func newlinesAndSemicolonsCombine() {
    #expect(significantLines("let x = 1; let y = 2\nlet z = 3") == 3)
  }

  @Test
  func carriageReturnNewlineIsNotDoubleCounted() {
    #expect(significantLines("a\r\nb\r\nc") == 3)
  }

  @Test
  func lineCommentsAreNotSignificant() {
    #expect(significantLines("// just a comment") == 0)
    #expect(significantLines("let x = 1 // trailing comment") == 1)
    #expect(significantLines("// leading comment\nlet x = 1") == 1)
  }

  @Test
  func delimitersInsideLineCommentsAreIgnored() {
    // The semicolons live in the comment, so they do not start new lines.
    #expect(significantLines("// a; b; c") == 0)
    #expect(significantLines("let x = 1 // a; b; c") == 1)
  }

  @Test
  func blockCommentsAreNotSignificant() {
    #expect(significantLines("/* a comment */") == 0)
    #expect(significantLines("/* line one\nline two */") == 0)
  }

  @Test
  func nestedBlockCommentsAreBalanced() {
    #expect(significantLines("/* outer /* inner */ still outer */") == 0)
    // Code after a fully-closed nested comment is still counted.
    #expect(significantLines("/* a /* b */ c */ let x = 1") == 1)
  }

  @Test
  func delimitersInsideBlockCommentsAreIgnored() {
    // Only the real semicolon between `a` and `b` splits; those in the comment do not.
    #expect(significantLines("a; /* ; ; ; */ b") == 2)
  }

  @Test
  func delimitersInsideStringLiteralsAreIgnored() {
    // Semicolons inside the string are content, not statement separators.
    #expect(significantLines(#"log("a; b; c")"#) == 1)
    // A semicolon after the closing quote is a real separator.
    #expect(significantLines(#"let x = "hi"; let y = 2"#) == 2)
  }

  @Test
  func escapedQuotesDoNotEndStringLiterals() {
    // The escaped quote keeps the string open, so the inner `;` stays content.
    #expect(significantLines("let x = \"a;\\\"b\"") == 1)
  }

  @Test
  func multilineStringLiteralCountsAsOneLine() {
    // The newlines and semicolon inside the multiline literal are content.
    let code = "let x = \"\"\"\nalpha; beta\ngamma\n\"\"\""
    #expect(significantLines(code) == 1)
  }

  @Test
  func rawStringDelimitersAreIgnored() {
    // The `;` inside the raw string is content; the one after it separates.
    #expect(significantLines(##"let x = #"a; b"#; foo()"##) == 2)
  }

  @Test
  func blankAndCommentOnlyLinesAreExcludedFromAMix() {
    #expect(significantLines("let x = 1\n\n// a comment\nlet y = 2") == 2)
  }

  @Test
  func malformedInputReturnsACountWithoutCrashing() {
    // The counter is total: unterminated literals must never trap, only yield a
    // best-effort count.
    #expect(significantLines(#"let x = "abc"#) == 1)
    #expect(significantLines("let x = 1\n/* unterminated") == 1)
  }

  /// Convenience wrapper for the function under test.
  private func significantLines(_ code: String) -> Int {
    ReplSourceMetadata.countSignificantLinesOfCode(in: code)
  }
}
