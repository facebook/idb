/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Grid-based coverage tracking for accessibility elements. Uses a coarse grid
/// (default 10pt cells) to track which areas of the screen are covered by
/// accessibility element frames; overlapping elements are handled correctly
/// (a cell is filled or not).
///
/// Filled from a serialized read rather than during the walk that produced it, so every backend gets
/// the same calculation from the same input. It stays mutable because remote-content discovery marks
/// into a live grid as it hit-tests, and asks it which points are already covered.
///
/// Created and used entirely from Swift, so it is a plain Swift class.
final class FBAccessibilityCoverageGrid {

  let screenBounds: CGRect
  let cellSize: CGFloat
  let width: UInt
  let height: UInt

  private var grid: [UInt8]

  /// Default grid cell size in points.
  static let defaultCellSize: CGFloat = 10.0

  /// Initialize with screen bounds and cell size (default 10pt). Returns nil if
  /// the bounds produce a zero-dimension grid.
  init?(screenBounds: CGRect, cellSize: CGFloat = FBAccessibilityCoverageGrid.defaultCellSize) {
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
  }

  /// Mark cells covered by the given frame. Handles out-of-bounds frames safely.
  func markFilled(with frame: CGRect) {
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
  func isFilled(at point: CGPoint) -> Bool {
    let relativeX = point.x - screenBounds.origin.x
    let relativeY = point.y - screenBounds.origin.y
    let cellX = Int(floor(relativeX / cellSize))
    let cellY = Int(floor(relativeY / cellSize))
    guard cellX >= 0, cellX < Int(width), cellY >= 0, cellY < Int(height) else {
      return false
    }
    return grid[cellY * Int(width) + cellX] != 0
  }

  /// Mark every element's frame, and its descendants'.
  ///
  /// The application root is skipped. It spans the screen by definition, so counting it would pin every
  /// read at full coverage and answer nothing — the question coverage exists to answer is how much of
  /// the screen the app's *content* accounts for, which is how a mostly-unexposed WebView shows up as a
  /// low number.
  ///
  /// A read that did not serialize the type cannot recognise the root, and one that did not serialize
  /// frames has nothing to mark; requesting coverage widens the key set so that neither happens
  /// (`FBAccessibilityRequestOptions.serializationKeys`).
  func markFilled(withElements elements: [FBAccessibilityDocumentElement]) {
    for element in elements {
      if (element.type ?? nil) != Self.applicationType, let rect = (element.frame ?? nil)?.rect {
        markFilled(with: rect)
      }
      markFilled(withElements: element.children ?? [])
    }
  }

  /// The normalized type of an application root — `FBAXRoleVocabulary.normalizeRole` strips the `AX`
  /// prefix, so this one spelling covers the `AXApplication` the accessibility backend reports and the
  /// `Application` the guest backends do.
  private static let applicationType = "Application"

  /// The proportion of `screenBounds` that `elements` cover, or `nil` when the bounds do not make a
  /// usable grid.
  static func ratio(of elements: [FBAccessibilityDocumentElement], screenBounds: CGRect) -> Double? {
    guard let grid = FBAccessibilityCoverageGrid(screenBounds: screenBounds) else {
      return nil
    }
    grid.markFilled(withElements: elements)
    return grid.ratio
  }

  /// This grid's coverage as a proportion, or `nil` for a degenerate grid with nothing to report.
  var ratio: Double? {
    let ratio = coverageRatio()
    return ratio >= 0 ? Double(ratio) : nil
  }

  /// Coverage ratio for the entire screen (0.0–1.0), or -1 if the grid is invalid.
  func coverageRatio() -> CGFloat {
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

extension FBAccessibilityCoverage {

  /// The coverage a read reports, measured over its serialized elements.
  ///
  /// The one definition, shared by every backend. Both ratios come from the same model the read
  /// returned, so a backend cannot accidentally measure something different from another — which is
  /// what a per-backend calculation had already allowed to happen once, when only the accessibility
  /// path had one at all.
  ///
  /// `nil` when the bounds are unusable, so an unmeasurable read reports nothing rather than zero.
  static func measured(
    reported: [FBAccessibilityDocumentElement],
    walked: [FBAccessibilityDocumentElement],
    screenBounds: CGRect,
    additional: Double? = nil
  ) -> FBAccessibilityCoverage? {
    guard let frame = FBAccessibilityCoverageGrid.ratio(of: reported, screenBounds: screenBounds),
      let walkedRatio = FBAccessibilityCoverageGrid.ratio(of: walked, screenBounds: screenBounds)
    else {
      return nil
    }
    return FBAccessibilityCoverage(frame: frame, walked: walkedRatio, additional: additional)
  }

  /// The bounds a read's screen info describes. The frames the calculation measures are in screen
  /// space, so the rectangle is anchored at the origin.
  static func bounds(of screen: FBAccessibilityScreenInfo) -> CGRect {
    CGRect(x: 0, y: 0, width: screen.width, height: screen.height)
  }
}
