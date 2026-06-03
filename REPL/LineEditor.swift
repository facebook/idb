/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

final class LineEditor {
  private var originalTermios = termios()
  private var isRawMode = false
  private let prompt = "> "

  func enableRawMode() {
    tcgetattr(STDIN_FILENO, &originalTermios)
    var raw = originalTermios
    raw.c_lflag &= ~UInt(ICANON | ECHO)
    raw.c_cc.16 = 1 // VMIN
    raw.c_cc.17 = 0 // VTIME
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    isRawMode = true
  }

  func disableRawMode() {
    if isRawMode {
      tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
      isRawMode = false
    }
  }

  func readLine() -> String? {
    enableRawMode()
    defer { disableRawMode() }

    var buffer: [Character] = []
    var cursor = 0

    write(STDOUT_FILENO, prompt, prompt.utf8.count)

    while true {
      var byte: UInt8 = 0
      guard read(STDIN_FILENO, &byte, 1) == 1 else { return nil }

      switch byte {
      case 0x0A, 0x0D: // Enter
        write(STDOUT_FILENO, "\n", 1)
        return String(buffer)

      case 0x7F, 0x08: // Backspace / Delete
        if cursor > 0 {
          cursor -= 1
          buffer.remove(at: cursor)
          redraw(buffer: buffer, cursor: cursor)
        }

      case 0x1B: // Escape sequence
        var seq: [UInt8] = [0, 0]
        guard read(STDIN_FILENO, &seq[0], 1) == 1 else { continue }
        guard read(STDIN_FILENO, &seq[1], 1) == 1 else { continue }
        if seq[0] == 0x5B { // '['
          switch seq[1] {
          case 0x43: // Right arrow
            if cursor < buffer.count {
              cursor += 1
              write(STDOUT_FILENO, "\u{1B}[C", 3)
            }
          case 0x44: // Left arrow
            if cursor > 0 {
              cursor -= 1
              write(STDOUT_FILENO, "\u{1B}[D", 3)
            }
          default:
            break
          }
        }

      case 0x04: // Ctrl-D
        if buffer.isEmpty { return nil }

      default:
        if byte >= 0x20 {
          let char = Character(UnicodeScalar(byte))
          buffer.insert(char, at: cursor)
          cursor += 1
          if cursor == buffer.count {
            var b = byte
            write(STDOUT_FILENO, &b, 1)
          } else {
            redraw(buffer: buffer, cursor: cursor)
          }
        }
      }
    }
  }

  private func redraw(buffer: [Character], cursor: Int) {
    write(STDOUT_FILENO, "\r\u{1B}[K", 4)
    let line = prompt + String(buffer)
    _ = line.withCString { ptr in
      write(STDOUT_FILENO, ptr, line.utf8.count)
    }
    let moveBack = buffer.count - cursor
    if moveBack > 0 {
      let seq = "\u{1B}[\(moveBack)D"
      _ = seq.withCString { ptr in
        write(STDOUT_FILENO, ptr, seq.utf8.count)
      }
    }
  }
}
