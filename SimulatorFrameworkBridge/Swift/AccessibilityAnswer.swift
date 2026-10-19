/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation

/// The guest's answer to a unary accessibility request: the outcome its verb answers with, built as the shared type
/// the host decodes it as, and encoded once to go on the wire.
public enum AccessibilityAnswer: Equatable, Sendable {
  case tree(BridgeAXOutcome<BridgeAXTreeResponse>)
  case hitTest(BridgeAXOutcome<BridgeAXHitTestResponse>)
  case write(BridgeAXOutcome<BridgeAXWriteResponse>)
  case setting(BridgeAXOutcome<BridgeAXSettingResponse>)
  case displays(BridgeAXOutcome<BridgeAXDisplayInventory>)
  /// A failure before any verb could answer, such as a request that did not decode or a raise while answering, which
  /// reads the same whatever the verb.
  case failure(BridgeAXFailure)

  public var succeeded: Bool {
    switch self {
    case let .tree(outcome): outcome.succeeded
    case let .hitTest(outcome): outcome.succeeded
    case let .write(outcome): outcome.succeeded
    case let .setting(outcome): outcome.succeeded
    case let .displays(outcome): outcome.succeeded
    case .failure: false
    }
  }

  /// The answer as the host receives it. One that cannot be encoded goes on the wire as a failure saying so: the guest
  /// serves a long-lived connection, so it must never abort or send nothing.
  public func encoded() -> Data {
    do {
      switch self {
      case let .tree(outcome): return try JSONEncoder().encode(outcome)
      case let .hitTest(outcome): return try JSONEncoder().encode(outcome)
      case let .write(outcome): return try JSONEncoder().encode(outcome)
      case let .setting(outcome): return try JSONEncoder().encode(outcome)
      case let .displays(outcome): return try JSONEncoder().encode(outcome)
      case let .failure(failure): return try failure.encodedOutcome()
      }
    } catch {
      NSLog("[AccessibilityService] could not encode an answer, sending a failure instead: %@", error as NSError)
      return Data(#"{"error":"response serialization failed","ok":false}"#.utf8)
    }
  }
}

extension BridgeAXOutcome {
  var succeeded: Bool {
    guard case .success = self else { return false }
    return true
  }
}

extension BridgeAXFailure {
  /// The failure as a frame, which reads the same whichever verb's outcome carries it.
  func encodedOutcome() throws -> Data {
    try JSONEncoder().encode(BridgeAXOutcome<BridgeAXSettingResponse>.failure(self))
  }
}
