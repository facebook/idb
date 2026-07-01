/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import FBSimulatorControl
import Foundation

/// Maps a REPL `host_command` -- a name plus JSON args that injected code sends
/// back to the companion *while* it runs -- to an `FBIDBCommandExecutor` call.
///
/// Returns `(success, resultJSON)`: on success, `resultJSON` is the command's
/// result value encoded as JSON (`"null"` when there is none); on failure, it is
/// an error message. Only safe, non-re-entrant commands are implemented; anything
/// else is reported as an unknown command (we never wire up `repl`/management
/// operations here).
struct HostCommandDispatcher {

  let commandExecutor: FBIDBCommandExecutor

  func run(name: String, args: [String: Any]) async -> (success: Bool, resultJSON: String) {
    do {
      switch name {
      case "tap":
        guard let x = args["x"] as? Double, let y = args["y"] as? Double else {
          return (false, "tap: expected numeric 'x' and 'y' arguments")
        }
        try await commandExecutor.hid(.tapAt(x: x, y: y))
        return (true, "null")

      case "describe_all":
        let response = try await commandExecutor.accessibility_info_at_point(nil, nestedFormat: false)
        let elementsData = try JSONSerialization.data(withJSONObject: response.elements)
        let elementsJSON = String(decoding: elementsData, as: UTF8.self)
        // Encode the elements JSON as a JSON string value so the host_result
        // `result` is the String that `IDB.describeAll()` returns verbatim.
        let resultData = try JSONSerialization.data(withJSONObject: elementsJSON, options: [.fragmentsAllowed])
        return (true, String(decoding: resultData, as: UTF8.self))

      default:
        return (false, "unknown host command '\(name)'")
      }
    } catch {
      return (false, "\(error)")
    }
  }
}
