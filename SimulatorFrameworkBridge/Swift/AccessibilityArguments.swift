/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation

public enum AXBridgeArguments {
  public static func request(action: String, arguments: [String]) -> [String: Any] {
    var request: [String: Any] = [BridgeAXWire.Request.verb.key: action]
    // The CLI consumes pairs, ignores unknown/dangling flags, and lets the last duplicate win.
    for index in stride(from: 0, to: max(0, arguments.count - 1), by: 2) {
      guard let field = BridgeAXWire.Request.allCases.first(where: { $0.flag == arguments[index] }) else {
        continue
      }
      request[field.key] = value(of: field, from: arguments[index + 1])
    }
    return request
  }

  /// The value a flag's argument carries, typed as the persistent transport sends that field.
  private static func value(of field: BridgeAXWire.Request, from argument: String) -> Any {
    let string = argument as NSString
    switch field {
    case .pid, .maxDepth, .maxNodes, .clientType, .busyThresholdMs, .quietWindowMs:
      return string.intValue
    case .automationMode, .explainUnreachable:
      return string.boolValue
    case .x, .y:
      return string.doubleValue
    case .displayID:
      guard let displayID = UInt32(argument), displayID > 0 else { return argument }
      return displayID
    case .attributes:
      return argument.components(separatedBy: ",")
    case .enabled:
      switch argument {
      case "true": return true
      case "false": return false
      default: return argument
      }
    case .verb, .traversal, .method, .action, .value, .setting, .assertKey, .assertValue:
      return argument
    }
  }
}
