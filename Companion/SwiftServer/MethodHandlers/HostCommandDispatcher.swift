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

/// The outcome of running a host command: on success, the serialized result
/// payload (empty when the command has no return value); on failure, the error.
enum HostCommandResult {
  case success(Data)
  case failure(Error)
}

/// An error raised while handling a host command (e.g. an invalid argument). Its
/// `description` is the message that reaches the REPL client.
enum HostCommandError: Error, CustomStringConvertible {
  case message(String)

  var description: String {
    switch self {
    case .message(let message):
      return message
    }
  }
}

/// Maps a decoded `ReplCommand` -- sent by injected REPL code while it runs -- to
/// an `FBIDBCommandExecutor` call.
///
/// Each command's logic (`resultValue(for:)`) produces its result as a value --
/// nothing, a `Codable` value, or a Foundation property-list object -- or throws.
/// `run` serializes that to the wire payload and turns a thrown error into a
/// failure, both in one place, so adding a command repeats none of that. Sharing
/// `ReplCommand` with the client (via `ReplProtocol`) keeps the switch exhaustive.
struct HostCommandDispatcher {

  let commandExecutor: FBIDBCommandExecutor

  /// The result a command produces, before serialization to the wire.
  private enum ResultValue {
    /// A `Codable` value; encoded as a binary property list.
    case encodable(any Encodable)
    /// A Foundation property-list object (e.g. the accessibility tree), already in
    /// a form `PropertyListSerialization` accepts.
    case propertyList(Any)
  }

  func run(_ command: ReplCommand) async -> HostCommandResult {
    do {
      switch try await resultValue(for: command) {
      case nil:
        return .success(Data())
      case .encodable(let value):
        return .success(try Self.propertyListData(encoding: value))
      case .propertyList(let object):
        return .success(try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0))
      }
    } catch {
      return .failure(error)
    }
  }

  /// Runs `command`, returning its result value, or nil when it has no return
  /// value. Throws on failure.
  private func resultValue(for command: ReplCommand) async throws -> ResultValue? {
    switch command {
    case .tap(let point):
      try await commandExecutor.hid(.tapAt(x: point.x, y: point.y))
      return nil

    case .tapMarker(let marker):
      try await commandExecutor.accessibility_tap(label: marker)
      return nil

    case .swipe(let from, let to, let duration, let delta):
      try await commandExecutor.hid(.swipe(from.x, yStart: from.y, xEnd: to.x, yEnd: to.y, delta: delta, duration: duration))
      return nil

    case .pinch(let center, let scale, let duration, let radius):
      try await commandExecutor.hid(.pinchAt(x: center.x, y: center.y, scale: scale, duration: duration, radius: radius))
      return nil

    case .button(let name):
      let normalized = name.replacingOccurrences(of: "-", with: "_").lowercased()
      guard let button = FBSimulatorHIDButton.allCases.first(where: { $0.name == normalized }) else {
        let valid = FBSimulatorHIDButton.allCases.map(\.name).joined(separator: ", ")
        throw HostCommandError.message("button: unknown button '\(name)' (expected one of: \(valid))")
      }
      try await commandExecutor.hid(.shortButtonPress(button))
      return nil

    case .text(let text):
      var events: [FBSimulatorHIDEvent] = []
      for character in text {
        guard let key = Self.hidKeyCode(for: character) else {
          throw HostCommandError.message("text: unsupported character '\(character)'")
        }
        if key.shift { events.append(.keyboard(direction: .down, keyCode: Self.leftShiftKeyCode)) }
        events.append(.keyboard(direction: .down, keyCode: key.code))
        events.append(.keyboard(direction: .up, keyCode: key.code))
        if key.shift { events.append(.keyboard(direction: .up, keyCode: Self.leftShiftKeyCode)) }
      }
      try await commandExecutor.hid(.composite(events))
      return nil

    // touch-move uses the same `.down` primitive as touch-down at a new point;
    // a sequence of down -> move(s) -> up forms a held drag (the HID connection
    // is cached on the simulator, so it persists across these commands).
    case .touchDown(let point), .touchMove(let point):
      try await commandExecutor.hid(.touch(direction: .down, x: point.x, y: point.y))
      return nil

    case .touchUp(let point):
      try await commandExecutor.hid(.touch(direction: .up, x: point.x, y: point.y))
      return nil

    case .describeAll:
      let response = try await commandExecutor.accessibility_info_at_point(nil, nestedFormat: true)
      // Adapt the serializer's tree for the client: drop nulls and render each
      // node's AXValue as a String (see `replAccessibilityTree`). Only describe_all
      // needs this.
      let tree = Self.replAccessibilityTree(from: response.elements) ?? [String: Any]()
      return .propertyList(tree)
    }
  }

  /// Encodes a `Codable` value as a binary property list. Generic so the
  /// existential from `ResultValue.encodable` is opened to a concrete type, which
  /// `PropertyListEncoder.encode` requires.
  private static func propertyListData<Value: Encodable>(encoding value: Value) throws -> Data {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    return try encoder.encode(value)
  }

  /// Adapts the shared serializer's accessibility tree for the REPL client: drops
  /// the `NSNull`s it emits for absent attributes (a property list has no null type,
  /// and `AXElement`'s fields are optional so a missing key reads as nil), and
  /// renders each node's `AXValue` as a String, so the client decodes a plain
  /// optional String rather than a string/number/bool union.
  private static func replAccessibilityTree(from value: Any) -> Any? {
    if value is NSNull {
      return nil
    }
    if var dictionary = value as? [String: Any] {
      dictionary = dictionary.compactMapValues(replAccessibilityTree(from:))
      if let axValue = dictionary["AXValue"] {
        dictionary["AXValue"] = Self.stringForAXValue(axValue)
      }
      return dictionary
    }
    if let array = value as? [Any] {
      return array.compactMap(replAccessibilityTree(from:))
    }
    return value
  }

  /// Renders an `AXValue` as a String, preserving boolean semantics
  /// (`"true"`/`"false"`) rather than letting a property-list Boolean become "1"/"0".
  private static func stringForAXValue(_ value: Any) -> String {
    if CFGetTypeID(value as AnyObject) == CFBooleanGetTypeID() {
      return (value as? Bool ?? false) ? "true" : "false"
    }
    return String(describing: value)
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
