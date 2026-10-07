/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The terminal cells a frame is sampled into. Each cell carries two vertically stacked pixels, and
/// terminal cells are roughly twice as tall as they are wide, so a cell's two pixels are close to
/// square and a surface keeps its aspect ratio without correction.
public struct TerminalGrid: Equatable, Sendable {
  public let columns: Int
  public let rows: Int

  public init(columns: Int, rows: Int) {
    self.columns = max(1, columns)
    self.rows = max(1, rows)
  }

  public var cellCount: Int { columns * rows }

  /// The largest grid with the surface's aspect ratio that fits within the terminal.
  public static func fitting(surfaceWidth: Int, surfaceHeight: Int, terminalColumns: Int, terminalRows: Int) -> TerminalGrid {
    guard surfaceWidth > 0, surfaceHeight > 0 else {
      return TerminalGrid(columns: terminalColumns, rows: terminalRows)
    }
    let aspect = Double(surfaceHeight) / Double(surfaceWidth)
    let rowsAtFullWidth = Double(terminalColumns) * aspect / 2
    if rowsAtFullWidth <= Double(terminalRows) {
      return TerminalGrid(columns: terminalColumns, rows: Int(rowsAtFullWidth.rounded()))
    }
    return TerminalGrid(columns: min(terminalColumns, Int((Double(terminalRows) * 2 / aspect).rounded())), rows: terminalRows)
  }
}

/// The averaged colours of the top and bottom halves of one terminal cell. Laid out to match the
/// sampler kernel's output record.
public struct TerminalCell: Equatable, Sendable {
  public var top: SIMD4<UInt8>
  public var bottom: SIMD4<UInt8>

  public init(top: SIMD4<UInt8>, bottom: SIMD4<UInt8>) {
    self.top = top
    self.bottom = bottom
  }
}
