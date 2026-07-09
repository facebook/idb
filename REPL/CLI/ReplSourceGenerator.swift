/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// patternlint-disable cdecl-unsupported

import Foundation

/// Turns a line (or block) of user-entered REPL Swift into a compilable source
/// file: it lifts the `import` statements out of the body, wraps the remaining
/// code in a `@_cdecl` entry point the companion injects and calls, and re-applies
/// the imports at file scope so the modules they name resolve.
///
/// Every step is a pure function free of I/O or `ReplRunner` state, so the parsing
/// and generation can be unit-tested directly.
enum ReplSourceGenerator {

  /// The full compilable source for the submission at `index`: the user's imports
  /// (plus Foundation, which the generated wrapper needs) at file scope, followed
  /// by their remaining code wrapped in the `idb_repl_<index>` entry point.
  ///
  /// `autoImportModules` are imported at file scope alongside the user's own
  /// imports, so injected code can reference the test bundle's modules (one per
  /// probe-generated `<Module>.swiftinterface`) without an explicit `import`.
  static func generateSource(for code: String, index: Int, autoImportModules: [String] = []) -> String {
    let (imports, body) = extractImports(from: code)
    return wrappedCode(swiftCode: body, imports: autoImportModules + imports, index: index)
  }

  /// Splits `code` into the module names it imports and the same code with those
  /// import statements removed.
  static func extractImports(from code: String) -> (imports: [String], strippedCode: String) {
    let pattern = #"(?:@\w+\s+)?import\s+([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\s*;?"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return ([], code)
    }
    let nsCode = code as NSString
    let range = NSRange(location: 0, length: nsCode.length)
    let imports = regex.matches(in: code, range: range).map { match in
      nsCode.substring(with: match.range(at: 1))
    }
    let stripped = regex.stringByReplacingMatches(in: code, range: range, withTemplate: "")
    return (imports, stripped)
  }

  /// Whether `code` uses `async`/`await`, so the wrapper must bridge it to a
  /// synchronous entry point.
  static func containsAsync(_ code: String) -> Bool {
    let pattern = #"\b(?:async|await)\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return false
    }
    let nsCode = code as NSString
    return regex.firstMatch(in: code, range: NSRange(location: 0, length: nsCode.length)) != nil
  }

  // MARK: - Private

  private static func wrappedCode(swiftCode: String, imports: [String], index: Int) -> String {
    let function =
      containsAsync(swiftCode)
      ? asyncFunction(swiftCode: swiftCode, index: index)
      : syncFunction(swiftCode: swiftCode, index: index)
    // Re-apply the imports stripped from the user's code so the modules they
    // reference resolve. Foundation is always needed by the generated wrapper;
    // dedupe so a user-supplied `import Foundation` is not emitted twice.
    var modules = ["Foundation"]
    for module in imports where !modules.contains(module) {
      modules.append(module)
    }
    let importLines = modules.map { "import \($0) // idb-repl-strip" }.joined(separator: "\n")
    return """
      \(importLines)
      \(function)
      """
  }

  private static func syncFunction(swiftCode: String, index: Int) -> String {
    return """
      private func userCode_\(index)() throws -> Any { // idb-repl-strip
        \(swiftCode)
      } // idb-repl-strip
      @_cdecl("idb_repl_\(index)") public func idb_repl_\(index)() -> UnsafePointer<CChar>? { // idb-repl-strip
        let output: String // idb-repl-strip
        do { // idb-repl-strip
          let result = try userCode_\(index)() // idb-repl-strip
          output = "Result:\\n\\(String(describing: result))" // idb-repl-strip
        } catch { // idb-repl-strip
          output = "Exception:\\n\\(String(describing: error))" // idb-repl-strip
        } // idb-repl-strip
        return output.withCString { UnsafePointer(strdup($0)) } // idb-repl-strip
      } // idb-repl-strip
      """
  }

  private static func asyncFunction(swiftCode: String, index: Int) -> String {
    return """
      private func userCode_\(index)() async throws -> Any { // idb-repl-strip
        \(swiftCode)
      } // idb-repl-strip
      @_cdecl("idb_repl_\(index)") public func idb_repl_\(index)() -> UnsafePointer<CChar>? { // idb-repl-strip
        final class _Box: @unchecked Sendable { var value: Result<Any, Error> = .success("()") } // idb-repl-strip
        let box = _Box() // idb-repl-strip
        let semaphore = DispatchSemaphore(value: 0) // idb-repl-strip
        Task { // idb-repl-strip
          do { box.value = .success(try await userCode_\(index)()) } // idb-repl-strip
          catch { box.value = .failure(error) } // idb-repl-strip
          semaphore.signal() // idb-repl-strip
        } // idb-repl-strip
        semaphore.wait() // idb-repl-strip
        let output: String // idb-repl-strip
        do { // idb-repl-strip
          let result = try box.value.get() // idb-repl-strip
          output = "Result:\\n\\(String(describing: result))" // idb-repl-strip
        } catch { // idb-repl-strip
          output = "Exception:\\n\\(String(describing: error))" // idb-repl-strip
        } // idb-repl-strip
        return output.withCString { UnsafePointer(strdup($0)) } // idb-repl-strip
      } // idb-repl-strip
      """
  }
}
