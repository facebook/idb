/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Errors thrown by the simulator accessibility command surface.
///
/// Typed cases let callers pattern-match (`catch FBAccessibilityError.elementNotFound`),
/// while `LocalizedError.errorDescription` preserves the human-readable messages that
/// flow through `error.localizedDescription` (sime2e output, gRPC status, logs).
public enum FBAccessibilityError: LocalizedError, Sendable {

  /// An operation was attempted on an element handle that has been closed.
  /// `operation` is the verb phrase, e.g. "serialize", "tap", "set value on".
  case closedElement(operation: String)

  /// The requested searchable key had no string value on the element.
  case noStringValue(key: String)

  /// The element does not support an accessibility press.
  case pressUnsupported(supportedActions: String)

  /// `accessibilityPerformPress` returned `false`.
  case pressFailed

  /// No descendant matched the search within the depth bound.
  case elementNotFound(key: String, value: String, depth: UInt)

  /// The owning simulator was deallocated before the operation completed.
  case simulatorDeallocated

  /// The simulator is not booted.
  case simulatorNotBooted(description: String)

  /// The host lacks the CoreSimulator accessibility API (Xcode 12+ required).
  case accessibilityUnavailable

  /// The accessibility translation dispatcher could not be resolved.
  case dispatcherUnavailable

  /// CoreSimulator returned no translation object for the request.
  case noTranslationObject

  /// SpringBoard crashed and the CoreSimulatorBridge restart that would recover it failed.
  case springBoardRemediationFailed(serviceName: String)

  public var errorDescription: String? {
    switch self {
    case .closedElement(let operation):
      return "Cannot \(operation) a closed element"
    case .noStringValue(let key):
      return "No string value for key \(key)"
    case .pressUnsupported(let supportedActions):
      return "Element does not support pressing. Supported: \(supportedActions)"
    case .pressFailed:
      return "accessibilityPerformPress did not succeed"
    case .elementNotFound(let key, let value, let depth):
      return "Element with \(key) containing '\(value)' not found within depth \(depth)"
    case .simulatorDeallocated:
      return "Simulator deallocated"
    case .simulatorNotBooted(let description):
      return "Cannot run accessibility commands against \(description) as it is not booted"
    case .accessibilityUnavailable:
      return "-[SimDevice sendAccessibilityRequestAsync:completionQueue:completionHandler:] is not present on this host, you must install and/or use Xcode 12 to use accessibility."
    case .dispatcherUnavailable:
      return "Accessibility translation dispatcher is unavailable"
    case .noTranslationObject:
      return "No translation object returned for simulator. This means you have likely specified a point onscreen that is invalid or invisible due to a fullscreen dialog"
    case .springBoardRemediationFailed(let serviceName):
      return "SpringBoard has crashed; could not restart \(serviceName) to recover the frontmost application's accessibility hierarchy."
    }
  }
}

extension FBAccessibilityError: CustomStringConvertible {
  /// Mirrors `errorDescription` so string interpolation (`"\(error)"`) and logs
  /// surface the human-readable message rather than the synthesized case name.
  public var description: String { errorDescription ?? "FBAccessibilityError" }
}
