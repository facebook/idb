/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Grid-based coverage tracking for accessibility elements. Uses a coarse grid
/// (default 10pt cells) to track which areas of the screen are covered by
/// accessibility element frames; overlapping elements are handled correctly
/// (a cell is filled or not) and coverage is computed incrementally during the
/// serialization traversal.
///
/// Still created and used by the Objective-C serializer in this module (via
/// `FBSimulatorControl-Swift.h`), so it keeps its `@objc` class name and selectors.
@objc(FBAccessibilityCoverageGrid)
public final class FBAccessibilityCoverageGrid: NSObject {

  @objc public let screenBounds: CGRect
  @objc public let cellSize: CGFloat
  @objc public let width: UInt
  @objc public let height: UInt

  private var grid: [UInt8]

  private static let defaultCellSize: CGFloat = 10.0

  /// Initialize with screen bounds and cell size. Returns nil if the bounds
  /// produce a zero-dimension grid.
  @objc(initWithScreenBounds:cellSize:)
  public init?(screenBounds: CGRect, cellSize: CGFloat) {
    let resolvedCellSize = cellSize > 0 ? cellSize : Self.defaultCellSize
    let computedWidth = UInt(ceil(screenBounds.size.width / resolvedCellSize))
    let computedHeight = UInt(ceil(screenBounds.size.height / resolvedCellSize))
    guard computedWidth > 0, computedHeight > 0 else {
      return nil
    }
    self.screenBounds = screenBounds
    self.cellSize = resolvedCellSize
    self.width = computedWidth
    self.height = computedHeight
    self.grid = [UInt8](repeating: 0, count: Int(computedWidth * computedHeight))
    super.init()
  }

  @objc(initWithScreenBounds:)
  public convenience init?(screenBounds: CGRect) {
    self.init(screenBounds: screenBounds, cellSize: Self.defaultCellSize)
  }

  /// Mark cells covered by the given frame. Handles out-of-bounds frames safely.
  @objc(markFilledWithFrame:)
  public func markFilled(with frame: CGRect) {
    guard !frame.isEmpty, !frame.isNull else {
      return
    }

    // Frame coordinates relative to the screen bounds origin.
    let relativeX = frame.origin.x - screenBounds.origin.x
    let relativeY = frame.origin.y - screenBounds.origin.y
    let relativeMaxX = relativeX + frame.size.width
    let relativeMaxY = relativeY + frame.size.height

    // Cell range, clamped to valid grid indices.
    var minX = Int(floor(relativeX / cellSize))
    var minY = Int(floor(relativeY / cellSize))
    var maxX = Int(floor(relativeMaxX / cellSize))
    var maxY = Int(floor(relativeMaxY / cellSize))
    minX = max(0, minX)
    minY = max(0, minY)
    maxX = min(Int(width) - 1, maxX)
    maxY = min(Int(height) - 1, maxY)

    guard minX <= maxX, minY <= maxY else {
      return
    }

    let rowWidth = Int(width)
    for y in minY...maxY {
      let rowStart = y * rowWidth
      for x in minX...maxX {
        grid[rowStart + x] = 1
      }
    }
  }

  /// Whether the cell containing the given point is filled. NO if empty or out of bounds.
  @objc(isFilledAtPoint:)
  public func isFilled(at point: CGPoint) -> Bool {
    let relativeX = point.x - screenBounds.origin.x
    let relativeY = point.y - screenBounds.origin.y
    let cellX = Int(floor(relativeX / cellSize))
    let cellY = Int(floor(relativeY / cellSize))
    guard cellX >= 0, cellX < Int(width), cellY >= 0, cellY < Int(height) else {
      return false
    }
    return grid[cellY * Int(width) + cellX] != 0
  }

  /// Coverage ratio for the entire screen (0.0–1.0), or -1 if the grid is invalid.
  @objc public func coverageRatio() -> CGFloat {
    let totalCells = Int(width * height)
    guard totalCells > 0 else {
      return -1
    }
    let filledCells = grid.reduce(into: 0) { count, cell in
      if cell != 0 { count += 1 }
    }
    return CGFloat(filledCells) / CGFloat(totalCells)
  }
}
