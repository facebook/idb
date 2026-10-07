/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum TerminalRenderMode: String, Sendable, CaseIterable {
  /// `▀` with the top pixel as foreground and the bottom as background: two colour samples per cell.
  case half
  /// A brightness ramp of ASCII characters coloured by the cell's average.
  case ascii
}

/// Turns sampled frames into truecolor ANSI output, writing only the cells that changed since the
/// last frame. A cell is redrawn when either half differs from what is on screen by more than
/// `threshold` in any channel; comparing against what was last written, rather than the previous
/// frame, means sub-threshold changes cannot accumulate into visible drift.
public struct ANSIFrameFormatter {
  public let mode: TerminalRenderMode
  public let threshold: UInt8

  private var onScreen: [TerminalCell]?
  private var onScreenGrid: TerminalGrid?

  public init(mode: TerminalRenderMode, threshold: UInt8) {
    self.mode = mode
    self.threshold = threshold
  }

  /// Forget what is on screen, so the next frame is written in full.
  public mutating func invalidate() {
    onScreen = nil
    onScreenGrid = nil
  }

  /// The bytes that bring the screen's top-left `grid` from what was last written to `cells`: none
  /// when no cell changed. A change of grid clears the screen and writes every cell.
  public mutating func format(_ cells: [TerminalCell], grid: TerminalGrid) -> [UInt8] {
    precondition(cells.count == grid.cellCount)
    var writer = SGRWriter()
    if grid != onScreenGrid {
      writer.append("\u{1B}[2J")
      onScreen = nil
    }
    var screen = onScreen ?? cells
    let full = onScreen == nil
    var wroteCell = false
    for row in 0..<grid.rows {
      var cursorColumn: Int?
      for column in 0..<grid.columns {
        let index = row * grid.columns + column
        let cell = cells[index]
        if !full && !exceedsThreshold(screen[index], cell) {
          continue
        }
        if cursorColumn != column {
          writer.append("\u{1B}[\(row + 1);\(column + 1)H")
        }
        emit(cell, into: &writer)
        screen[index] = cell
        cursorColumn = column + 1
        wroteCell = true
      }
    }
    onScreen = screen
    onScreenGrid = grid
    guard wroteCell else { return [] }
    writer.append("\u{1B}[0m")
    return writer.bytes
  }

  private func exceedsThreshold(_ a: TerminalCell, _ b: TerminalCell) -> Bool {
    let limit = SIMD4<UInt8>(repeating: threshold)
    return any(absoluteDifference(a.top, b.top) .> limit) || any(absoluteDifference(a.bottom, b.bottom) .> limit)
  }

  private func absoluteDifference(_ a: SIMD4<UInt8>, _ b: SIMD4<UInt8>) -> SIMD4<UInt8> {
    pointwiseMax(a, b) &- pointwiseMin(a, b)
  }

  private static let ramp = Array(" .:-=+*#%@".utf8)
  private static let upperHalfBlock = Array("▀".utf8)

  private func emit(_ cell: TerminalCell, into writer: inout SGRWriter) {
    switch mode {
    case .half:
      writer.foreground(cell.top)
      writer.background(cell.bottom)
      writer.bytes.append(contentsOf: Self.upperHalfBlock)
    case .ascii:
      let average = SIMD4<UInt8>(truncatingIfNeeded: (SIMD4<UInt16>(truncatingIfNeeded: cell.top) &+ SIMD4<UInt16>(truncatingIfNeeded: cell.bottom)) / 2)
      let luma = (0.2126 * Double(average.x) + 0.7152 * Double(average.y) + 0.0722 * Double(average.z)) / 255
      writer.foreground(average)
      writer.bytes.append(Self.ramp[min(Self.ramp.count - 1, Int(luma * Double(Self.ramp.count)))])
    }
  }
}

/// Accumulates output, eliding colour escapes that would set the colour already in effect.
private struct SGRWriter {
  var bytes: [UInt8] = []
  private var foregroundColor: SIMD4<UInt8>?
  private var backgroundColor: SIMD4<UInt8>?

  mutating func append(_ string: String) {
    bytes.append(contentsOf: string.utf8)
  }

  mutating func foreground(_ color: SIMD4<UInt8>) {
    guard color != foregroundColor else { return }
    append("\u{1B}[38;2;\(color.x);\(color.y);\(color.z)m")
    foregroundColor = color
  }

  mutating func background(_ color: SIMD4<UInt8>) {
    guard color != backgroundColor else { return }
    append("\u{1B}[48;2;\(color.x);\(color.y);\(color.z)m")
    backgroundColor = color
  }
}
