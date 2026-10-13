/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBSimulatorControl
import Foundation

/// The screen a translator tree read is placed on: the bounds its frames are measured against, and the
/// screen the response reports. Resolved once per read, from the routed display when there is one and the
/// root element's own frame when there is not.
struct AXReadScreen: Equatable {
  let bounds: CGRect
  /// Nil for degenerate bounds, so an unknown screen is reported as unknown rather than zero-sized.
  let info: AccessibilityScreenInfo?

  init(display: AXTranslationDisplay?, rootFrame: CGRect) {
    let bounds = display?.bounds ?? rootFrame
    self.bounds = bounds
    self.info = display?.screen ?? Self.screenInfo(fromBounds: bounds)
  }

  static func screenInfo(fromBounds bounds: CGRect) -> AccessibilityScreenInfo? {
    guard bounds.width > 0, bounds.height > 0 else {
      return nil
    }
    return AccessibilityScreenInfo(width: Double(bounds.width), height: Double(bounds.height))
  }
}

/// The grid remote-content discovery hit-tests: the region it samples, how far apart its points are, and
/// how many it may visit. Unset options mean the whole screen, every 50 points, without a cap.
struct AXRemoteContentPlan: Equatable {
  static let defaultStepSize: CGFloat = 50

  let region: CGRect
  let stepSize: CGFloat
  /// 0 visits every point.
  let maxPoints: UInt

  init(_ options: AccessibilityRemoteContentOptions, screenBounds: CGRect) {
    self.region = options.region.isNull ? screenBounds : options.region
    self.stepSize = options.gridStepSize > 0 ? options.gridStepSize : Self.defaultStepSize
    self.maxPoints = options.maxPoints
  }

  /// Every grid point, row by row, inset one step from each edge of the region.
  var points: [CGPoint] {
    stride(from: stepSize, to: region.size.height - stepSize, by: stepSize).flatMap { y in
      stride(from: stepSize, to: region.size.width - stepSize, by: stepSize).map { x in
        CGPoint(x: region.origin.x + x, y: region.origin.y + y)
      }
    }
  }

  /// Whether `visited` points exhaust the cap.
  func isExhausted(afterVisiting visited: UInt) -> Bool {
    maxPoints > 0 && visited >= maxPoints
  }
}
