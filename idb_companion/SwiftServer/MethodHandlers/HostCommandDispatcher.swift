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
        if let marker = args["marker"] as? String {
          try await commandExecutor.accessibility_tap(label: marker)
          return (true, "null")
        }
        guard let x = args["x"] as? Double, let y = args["y"] as? Double else {
          return (false, "tap: expected numeric 'x' and 'y' arguments, or a 'marker' string")
        }
        try await commandExecutor.hid(.tapAt(x: x, y: y))
        return (true, "null")

      case "swipe":
        guard let startX = args["start_x"] as? Double, let startY = args["start_y"] as? Double,
          let endX = args["end_x"] as? Double, let endY = args["end_y"] as? Double
        else {
          return (false, "swipe: expected numeric 'start_x', 'start_y', 'end_x', 'end_y' arguments")
        }
        let delta = args["delta"] as? Double ?? 0
        let swipeDuration = args["duration"] as? Double ?? 0
        try await commandExecutor.hid(.swipe(startX, yStart: startY, xEnd: endX, yEnd: endY, delta: delta, duration: swipeDuration))
        return (true, "null")

      case "pinch":
        guard let x = args["x"] as? Double, let y = args["y"] as? Double, let scale = args["scale"] as? Double else {
          return (false, "pinch: expected numeric 'x', 'y', 'scale' arguments")
        }
        let pinchDuration = args["duration"] as? Double ?? 0.5
        let radius = args["radius"] as? Double ?? 100
        try await commandExecutor.hid(.pinchAt(x: x, y: y, scale: scale, duration: pinchDuration, radius: radius))
        return (true, "null")

      case "button":
        guard let buttonName = args["button"] as? String else {
          return (false, "button: expected a string 'button' argument")
        }
        let normalized = buttonName.replacingOccurrences(of: "-", with: "_").lowercased()
        guard let button = FBSimulatorHIDButton.allCases.first(where: { $0.name == normalized }) else {
          let valid = FBSimulatorHIDButton.allCases.map(\.name).joined(separator: ", ")
          return (false, "button: unknown button '\(buttonName)' (expected one of: \(valid))")
        }
        try await commandExecutor.hid(.shortButtonPress(button))
        return (true, "null")

      case "text":
        guard let text = args["text"] as? String else {
          return (false, "text: expected a string 'text' argument")
        }
        var events: [FBSimulatorHIDEvent] = []
        for character in text {
          guard let key = Self.hidKeyCode(for: character) else {
            return (false, "text: unsupported character '\(character)'")
          }
          if key.shift { events.append(.keyboard(direction: .down, keyCode: Self.leftShiftKeyCode)) }
          events.append(.keyboard(direction: .down, keyCode: key.code))
          events.append(.keyboard(direction: .up, keyCode: key.code))
          if key.shift { events.append(.keyboard(direction: .up, keyCode: Self.leftShiftKeyCode)) }
        }
        try await commandExecutor.hid(.composite(events))
        return (true, "null")

      // touch-move uses the same `.down` primitive as touch-down at a new point;
      // a sequence of down → move(s) → up forms a held drag (the HID connection
      // is cached on the simulator, so it persists across these commands).
      case "touch_down", "touch_move":
        guard let x = args["x"] as? Double, let y = args["y"] as? Double else {
          return (false, "\(name): expected numeric 'x' and 'y' arguments")
        }
        try await commandExecutor.hid(.touch(direction: .down, x: x, y: y))
        return (true, "null")

      case "touch_up":
        guard let x = args["x"] as? Double, let y = args["y"] as? Double else {
          return (false, "touch_up: expected numeric 'x' and 'y' arguments")
        }
        try await commandExecutor.hid(.touch(direction: .up, x: x, y: y))
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

  /// USB HID left-shift usage code, held to produce shifted characters.
  private static let leftShiftKeyCode: UInt32 = 0xE1

  /// Maps an ASCII character to its USB HID keyboard usage code (page 0x07) and
  /// whether shift must be held. Returns nil for characters with no single-key
  /// mapping.
  private static func hidKeyCode(for character: Character) -> (code: UInt32, shift: Bool)? {
    if let ascii = character.asciiValue {
      switch ascii {
      case 0x61...0x7A: return (UInt32(ascii - 0x61) + 0x04, false) // a-z
      case 0x41...0x5A: return (UInt32(ascii - 0x41) + 0x04, true) // A-Z
      case 0x31...0x39: return (UInt32(ascii - 0x31) + 0x1E, false) // 1-9
      default: break
      }
    }
    switch character {
    case "0": return (0x27, false)
    case " ": return (0x2C, false)
    case "\n": return (0x28, false)
    case "\t": return (0x2B, false)
    case "-": return (0x2D, false)
    case "=": return (0x2E, false)
    case "[": return (0x2F, false)
    case "]": return (0x30, false)
    case "\\": return (0x31, false)
    case ";": return (0x33, false)
    case "'": return (0x34, false)
    case "`": return (0x35, false)
    case ",": return (0x36, false)
    case ".": return (0x37, false)
    case "/": return (0x38, false)
    case "!": return (0x1E, true)
    case "@": return (0x1F, true)
    case "#": return (0x20, true)
    case "$": return (0x21, true)
    case "%": return (0x22, true)
    case "^": return (0x23, true)
    case "&": return (0x24, true)
    case "*": return (0x25, true)
    case "(": return (0x26, true)
    case ")": return (0x27, true)
    case "_": return (0x2D, true)
    case "+": return (0x2E, true)
    case "{": return (0x2F, true)
    case "}": return (0x30, true)
    case "|": return (0x31, true)
    case ":": return (0x33, true)
    case "\"": return (0x34, true)
    case "~": return (0x35, true)
    case "<": return (0x36, true)
    case ">": return (0x37, true)
    case "?": return (0x38, true)
    default: return nil
    }
  }
}
