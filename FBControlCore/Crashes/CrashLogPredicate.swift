/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Selects crash logs. Predicates compose with `&&`, `!` and `allOf(_:)`, and describe themselves
/// so that a query can be reported in errors.
public struct CrashLogPredicate: Sendable, CustomStringConvertible {
  public let description: String
  private let test: @Sendable (CrashLogInfo) -> Bool

  public init(description: String, _ test: @escaping @Sendable (CrashLogInfo) -> Bool) {
    self.description = description
    self.test = test
  }

  public func matches(_ crashLog: CrashLogInfo) -> Bool {
    test(crashLog)
  }

  // MARK: - Predicates

  public static let all = CrashLogPredicate(description: "all") { _ in true }

  public static let none = CrashLogPredicate(description: "none") { _ in false }

  public static func processIdentifier(_ processIdentifier: pid_t) -> CrashLogPredicate {
    CrashLogPredicate(description: "processIdentifier == \(processIdentifier)") { $0.processIdentifier == processIdentifier }
  }

  public static func newer(than date: Date) -> CrashLogPredicate {
    CrashLogPredicate(description: "date > \(date)") { date < $0.date }
  }

  public static func older(than date: Date) -> CrashLogPredicate {
    !newer(than: date)
  }

  public static func identifier(_ identifier: String) -> CrashLogPredicate {
    CrashLogPredicate(description: "identifier == \(identifier)") { $0.identifier == identifier }
  }

  public static func name(_ name: String) -> CrashLogPredicate {
    CrashLogPredicate(description: "name == \(name)") { $0.name == name }
  }

  /// A simulator's report names its udid in the executable's path, or, where macOS redacts that
  /// path, in the report's coalition.
  public static func simulatorUDID(_ udid: String) -> CrashLogPredicate {
    let coalitionName = "com.apple.CoreSimulator.SimDevice.\(udid)"
    return CrashLogPredicate(description: "simulator == \(udid)") {
      $0.executablePath.contains(udid) || $0.coalitionName == coalitionName
    }
  }

  public static func executablePathContains(_ substring: String) -> CrashLogPredicate {
    CrashLogPredicate(description: "executablePath contains \(substring)") { $0.executablePath.contains(substring) }
  }

  // MARK: - Composition

  public static func && (lhs: CrashLogPredicate, rhs: CrashLogPredicate) -> CrashLogPredicate {
    allOf([lhs, rhs])
  }

  public static prefix func ! (predicate: CrashLogPredicate) -> CrashLogPredicate {
    CrashLogPredicate(description: "!(\(predicate))") { !predicate.matches($0) }
  }

  /// Matches what every one of `predicates` matches; matches everything when it is empty.
  public static func allOf(_ predicates: [CrashLogPredicate]) -> CrashLogPredicate {
    guard predicates.count != 1 else {
      return predicates[0]
    }
    guard !predicates.isEmpty else {
      return .all
    }
    return CrashLogPredicate(description: "(\(predicates.map(\.description).joined(separator: " && ")))") { crashLog in
      predicates.allSatisfy { $0.matches(crashLog) }
    }
  }
}
