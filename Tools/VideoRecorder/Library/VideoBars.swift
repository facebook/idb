/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorControl
import Foundation

public struct VideoBars {
  public let bars: [String]
  public let barStats: [String]

  public init(bars: [String], barStats: [String]) {
    self.bars = bars
    self.barStats = barStats
  }

  /// Parse `--bar` arguments (and the deprecated status-bar flags) into per-bar (position, height,
  /// mode) triples, the effective `--bar-stats` positions, and the pad-mode edge insets.
  public func resolve(deprecatedBottomStatusBar: Bool, deprecatedTopStatusBar: Bool, logger: any ControlCoreLogger) -> (parsedBars: [(position: String, height: Int, mode: BarMode)], barStats: [String], edgeInsets: VideoStreamEdgeInsets) {
    // Syntax: --bar <position>[:<size>][:<mode>] — size defaults to defaultBarHeight,
    // mode defaults to `pad`. Examples: `--bar top`, `--bar top:24`, `--bar top:24:overlay`.
    var parsedBars: [(position: String, height: Int, mode: BarMode)] = []
    for barArg in bars {
      let parts = barArg.split(separator: ":", maxSplits: 2)
      guard let first = parts.first else { continue }
      let position = String(first)
      var height = OverlayCoordinateTransform.defaultBarHeight
      var mode = BarMode.pad
      for part in parts.dropFirst() {
        if let parsedHeight = Int(part) {
          height = parsedHeight
        } else if let parsedMode = BarMode(rawValue: String(part)) {
          mode = parsedMode
        } else {
          logger.log("--bar \(position): unrecognised attribute '\(part)' — expected an integer size or one of [pad, overlay]")
        }
      }
      parsedBars.append((position: position, height: height, mode: mode))
    }
    var barStats = self.barStats
    if deprecatedBottomStatusBar {
      logger.log("--bottom-status-bar is deprecated; use --bar bottom --bar-stats bottom")
      if !parsedBars.contains(where: { $0.position == "bottom" }) {
        parsedBars.append((position: "bottom", height: OverlayCoordinateTransform.defaultBarHeight, mode: .pad))
      }
      if !barStats.contains("bottom") {
        barStats.append("bottom")
      }
    }
    if deprecatedTopStatusBar {
      logger.log("--top-status-bar is deprecated; use --bar top")
      if !parsedBars.contains(where: { $0.position == "top" }) {
        parsedBars.append((position: "top", height: OverlayCoordinateTransform.defaultBarHeight, mode: .pad))
      }
    }

    // Compute effective edge insets from pad-mode bars only. Overlay-mode bars draw on top of
    // simulator screen content and do not reserve canvas space.
    let padBars = parsedBars.filter { $0.mode == .pad }
    let topBarHeight = padBars.filter { $0.position == "top" }.map(\.height).reduce(0, +)
    let bottomBarHeight = padBars.filter { $0.position == "bottom" }.map(\.height).reduce(0, +)
    let leftBarHeight = padBars.filter { $0.position == "left" }.map(\.height).reduce(0, +)
    let rightBarHeight = padBars.filter { $0.position == "right" }.map(\.height).reduce(0, +)
    let edgeInsets = VideoStreamEdgeInsets(
      top: UInt(topBarHeight),
      bottom: UInt(bottomBarHeight),
      left: UInt(leftBarHeight),
      right: UInt(rightBarHeight)
    )
    return (parsedBars, barStats, edgeInsets)
  }
}
