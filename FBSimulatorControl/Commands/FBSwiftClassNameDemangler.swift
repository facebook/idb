/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Recovers a readable class name from the legacy `_Tt` Swift mangling — the spelling
/// `NSStringFromClass` reports for Swift classes, which is how SwiftUI-backed accessibility
/// elements otherwise surface as names like `_TtGC7SwiftUI15CellHostingView…`.
///
/// A deliberate subset of Swift demangling: element types on the accessibility wire are only ever
/// ObjC-runtime class names, so only the `_Tt` scheme appears — never full `$s…` symbol manglings.
/// The answer is the bare class name (`CellHostingView`), matching the readable names the role
/// vocabulary produces everywhere else, rather than a fully-qualified generic signature.
enum FBSwiftClassNameDemangler {

  /// The demangled class name, or the input unchanged when it is not a legacy-mangled Swift class
  /// name or cannot be parsed. Already-readable names pass through, so applying this twice is
  /// harmless.
  static func demangle(_ name: String) -> String {
    guard name.hasPrefix(mangledPrefix) else {
      return name
    }
    let segments = lengthPrefixedSegments(in: name)
    guard !segments.isEmpty else {
      return name
    }
    // A generic class mangles as GC<module><class><generic arguments…>, so the class name is the
    // first segment after the module — skipping private-context discriminators, which mangle ahead
    // of the class they scope. Every other shape (plain, nested, class-in-generic) ends on the
    // class name, so the last segment is the answer there.
    if name.hasPrefix(genericClassPrefix),
      let className = segments.dropFirst().first(where: { !isPrivateContextDiscriminator($0) })
    {
      return className
    }
    return segments[segments.count - 1]
  }

  private static let mangledPrefix = "_Tt"
  private static let genericClassPrefix = "_TtGC"

  /// A mangled name carries at most a handful of segments; the bound only guards against
  /// pathological input.
  private static let maxSegments = 20

  /// The run-length-encoded name segments: each is a one-or-two-digit decimal length followed by
  /// that many characters. A segment whose declared length overruns the string contributes nothing,
  /// and the characters a segment covers are consumed — a digit inside a name is part of the name,
  /// not a new length.
  private static func lengthPrefixedSegments(in name: String) -> [String] {
    var segments: [String] = []
    let characters = Array(name)
    var index = 0
    var passes = 0
    while index < characters.count, passes < maxSegments {
      guard let firstDigit = decimalValue(of: characters[index]) else {
        index += 1
        continue
      }
      passes += 1
      var length = firstDigit
      var cursor = index + 1
      if firstDigit > 0, cursor < characters.count, let secondDigit = decimalValue(of: characters[cursor]) {
        length = length * 10 + secondDigit
        cursor += 1
      }
      if length > 0, cursor + length <= characters.count {
        segments.append(String(characters[cursor..<(cursor + length)]))
      }
      index = cursor + length
    }
    return segments
  }

  private static func decimalValue(of character: Character) -> Int? {
    guard character.isASCII, let value = character.wholeNumberValue, (0...9).contains(value) else {
      return nil
    }
    return value
  }

  /// Whether a segment scopes a private declaration rather than naming one: a `$`-prefixed
  /// anonymous-context reference (a runtime pointer, unstable across launches) or a `_`-prefixed
  /// 32-digit hex file discriminator.
  private static func isPrivateContextDiscriminator(_ segment: String) -> Bool {
    if segment.hasPrefix("$") {
      return true
    }
    guard segment.count == 33, segment.hasPrefix("_") else {
      return false
    }
    return segment.dropFirst().allSatisfy(\.isHexDigit)
  }
}
