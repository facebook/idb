/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Geometry and routing captured together for a touch operation.
enum SimulatorHIDDisplay: Equatable, Sendable {
  /// The only integrated display, which input reaches without a digitizer target.
  case sole(SimulatorInteractionDisplay)
  /// The active one of several integrated displays, and the digitizer that reaches it.
  case selected(SimulatorDisplay, target: UInt32)

  var geometry: SimulatorDisplayGeometry {
    switch self {
    case let .sole(display): display.geometry
    case let .selected(display, _): display.geometry
    }
  }

  var digitizerTarget: UInt64 {
    switch self {
    case .sole: 0
    case let .selected(_, target): UInt64(target)
    }
  }

  func normalizedPoint(_ point: CGPoint) throws -> CGPoint {
    let point = try geometry.unrotatedPoint(from: point)
    return CGPoint(x: point.x * geometry.scale / geometry.bounds.width, y: point.y * geometry.scale / geometry.bounds.height)
  }

  func unrotatedEdge(_ edge: SimulatorHIDEdge) -> SimulatorHIDEdge {
    guard edge != .none else { return .none }
    let edges: [SimulatorHIDEdge] = [.top, .right, .bottom, .left]
    let turns: Int
    switch geometry.rotation {
    case .upright: turns = 0
    case .clockwise: turns = 3
    case .upsideDown: turns = 2
    case .counterclockwise: turns = 1
    }
    guard let index = edges.firstIndex(of: edge) else { return .none }
    return edges[(index + turns) % edges.count]
  }

  func hasSameConfiguration(as other: Self) -> Bool {
    switch (self, other) {
    case let (.sole(first), .sole(second)): first.hasSameConfiguration(as: second)
    case let (.selected(first, firstTarget), .selected(second, secondTarget)):
      first.hasSameConfiguration(as: second) && firstTarget == secondTarget
    case (.sole, .selected), (.selected, .sole): false
    }
  }
}
