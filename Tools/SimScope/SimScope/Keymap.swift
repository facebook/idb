/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit

/// Translates a macOS key event into a USB HID Keyboard/Keypad (page 0x07) usage + shift flag, which
/// is what a `SimulatorHIDEvent.keyboard` event delivers to the simulator (the DTUHID transport
/// passes the usage straight through). US-layout table; unmapped keys return nil (ignored).
enum Keymap {

  struct Key {
    let usage: UInt32
    let shift: Bool
  }

  /// Named USB HID keyboard usages used elsewhere (modifier + control keys).
  enum Usage {
    static let returnKey: UInt32 = 0x28
    static let escape: UInt32 = 0x29
    static let delete: UInt32 = 0x2A // Backspace
    static let tab: UInt32 = 0x2B
    static let space: UInt32 = 0x2C
    static let forwardDelete: UInt32 = 0x4C
    static let right: UInt32 = 0x4F
    static let left: UInt32 = 0x50
    static let down: UInt32 = 0x51
    static let up: UInt32 = 0x52
    static let leftShift: UInt32 = 0xE1
  }

  /// The HID key for a single character (US layout), for replaying typed text. Nil if unmapped.
  static func key(for character: Character) -> Key? {
    guard let entry = printable[character] else { return nil }
    return Key(usage: entry.usage, shift: entry.shift)
  }

  static func hidKey(for event: NSEvent) -> Key? {
    // Control keys by Mac virtual keycode (layout-independent positions).
    if let usage = controlUsage(forKeyCode: event.keyCode) {
      return Key(usage: usage, shift: false)
    }
    // Printable characters, mapped (with shift) from the produced character.
    guard let character = event.characters?.unicodeScalars.first.map(Character.init),
      let entry = Self.printable[character]
    else {
      return nil
    }
    return Key(usage: entry.usage, shift: entry.shift)
  }

  private static func controlUsage(forKeyCode keyCode: UInt16) -> UInt32? {
    switch keyCode {
    case 36, 76: return Usage.returnKey // Return / keypad Enter
    case 48: return Usage.tab
    case 51: return Usage.delete // Backspace
    case 117: return Usage.forwardDelete
    case 53: return Usage.escape
    case 123: return Usage.left
    case 124: return Usage.right
    case 125: return Usage.down
    case 126: return Usage.up
    default: return nil
    }
  }

  private static let printable: [Character: (usage: UInt32, shift: Bool)] = {
    var table: [Character: (UInt32, Bool)] = [:]

    // Letters a–z (0x04–0x1D); uppercase shares the usage with shift.
    let letterBase: UInt32 = 0x04
    for (offset, lower) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
      let usage = letterBase + UInt32(offset)
      table[lower] = (usage, false)
      if let upper = lower.uppercased().first { table[upper] = (usage, true) }
    }

    // Number row 1–9,0 (0x1E–0x27) and their shifted symbols.
    let digitUsages: [UInt32] = [0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27]
    for (offset, digit) in "1234567890".enumerated() { table[digit] = (digitUsages[offset], false) }
    for (offset, symbol) in "!@#$%^&*()".enumerated() { table[symbol] = (digitUsages[offset], true) }

    table[" "] = (Usage.space, false)

    // Punctuation: (unshifted, shifted, usage).
    let punctuation: [(Character, Character, UInt32)] = [
      ("-", "_", 0x2D), ("=", "+", 0x2E), ("[", "{", 0x2F), ("]", "}", 0x30),
      ("\\", "|", 0x31), (";", ":", 0x33), ("'", "\"", 0x34), ("`", "~", 0x35),
      (",", "<", 0x36), (".", ">", 0x37), ("/", "?", 0x38),
    ]
    for (base, shifted, usage) in punctuation {
      table[base] = (usage, false)
      table[shifted] = (usage, true)
    }

    return table
  }()
}
