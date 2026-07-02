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
import ReplProtocol

/// Maps a decoded `ReplCommand` -- sent by injected REPL code while it runs -- to
/// an `FBIDBCommandExecutor` call.
///
/// Returns `(success, resultJSON)`: on success, `resultJSON` is the command's
/// result value encoded as JSON (`"null"` when there is none); on failure, it is
/// an error message. Sharing `ReplCommand` with the client (via `ReplProtocol`)
/// makes this switch exhaustive -- adding a command is a compile-time change here
/// as well as on the client.
struct HostCommandDispatcher {

  let commandExecutor: FBIDBCommandExecutor

  func run(_ command: ReplCommand) async -> (success: Bool, resultJSON: String) {
    do {
      switch command {
      case .tap(let point):
        try await commandExecutor.hid(.tapAt(x: point.x, y: point.y))
        return (true, "null")

      case .tapMarker(let marker):
        try await commandExecutor.accessibility_tap(label: marker)
        return (true, "null")

      case .swipe(let from, let to, let duration, let delta):
        try await commandExecutor.hid(.swipe(from.x, yStart: from.y, xEnd: to.x, yEnd: to.y, delta: delta, duration: duration))
        return (true, "null")

      case .pinch(let center, let scale, let duration, let radius):
        try await commandExecutor.hid(.pinchAt(x: center.x, y: center.y, scale: scale, duration: duration, radius: radius))
        return (true, "null")

      case .button(let name):
        let normalized = name.replacingOccurrences(of: "-", with: "_").lowercased()
        guard let button = FBSimulatorHIDButton.allCases.first(where: { $0.name == normalized }) else {
          let valid = FBSimulatorHIDButton.allCases.map(\.name).joined(separator: ", ")
          return (false, "button: unknown button '\(name)' (expected one of: \(valid))")
        }
        try await commandExecutor.hid(.shortButtonPress(button))
        return (true, "null")

      case .text(let text):
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
      // a sequence of down -> move(s) -> up forms a held drag (the HID connection
      // is cached on the simulator, so it persists across these commands).
      case .touchDown(let point), .touchMove(let point):
        try await commandExecutor.hid(.touch(direction: .down, x: point.x, y: point.y))
        return (true, "null")

      case .touchUp(let point):
        try await commandExecutor.hid(.touch(direction: .up, x: point.x, y: point.y))
        return (true, "null")

      case .describeAll:
        let response = try await commandExecutor.accessibility_info_at_point(nil, nestedFormat: false)
        let elementsData = try JSONSerialization.data(withJSONObject: response.elements)
        // The elements JSON is the string `IDB.describeAll()` returns verbatim;
        // it rides in the host_result's `result` field as-is.
        return (true, String(decoding: elementsData, as: UTF8.self))
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
