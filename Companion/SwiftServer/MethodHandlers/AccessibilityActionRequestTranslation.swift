/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import FBSimulatorControl
import Foundation
import GRPC
import IDBGRPCSwift

/// Translates an `accessibility_action` request to a checked `Action`. Rejects shapes no action accepts
/// (a missing target, a drag onto its own source, a negative duration).
enum AccessibilityActionRequestTranslation {

  /// A request that has been checked, with every endpoint and option resolved.
  enum Action: Equatable {
    case tap(query: FBAccessibilityElementQuery, expectedValue: String?, expectedKey: FBAXSearchableKey)
    case scroll(query: FBAccessibilityElementQuery, direction: FBAccessibilityScrollDirection)
    case setValue(query: FBAccessibilityElementQuery, value: String)
    case drag(source: FBAccessibilityElementQuery, destination: FBAccessibilityElementQuery, options: FBDragOptions)
  }

  static func action(from request: Idb_AccessibilityActionRequest) throws -> Action {
    switch request.action {
    case let .tap(tap):
      return .tap(
        query: try requiredQuery(from: request, action: "tap"),
        expectedValue: tap.checkExpectedValue ? tap.expectedValue : nil,
        expectedKey: try searchableKey(from: tap.expectedKey))
    case let .scroll(scroll):
      return .scroll(
        query: try targetedQuery(from: request) ?? .frontmost,
        direction: try scrollDirection(from: scroll.direction))
    case let .setValue(setValue):
      return .setValue(query: try requiredQuery(from: request, action: "set_value"), value: setValue.value)
    case let .drag(drag):
      return try dragAction(request: request, drag: drag)
    case .none:
      // Also what an action this companion is too old to know reads as: proto3 deserializes an
      // unrecognized oneof member as unset. Say so, rather than reporting an empty request.
      throw GRPCStatus(
        code: .invalidArgument,
        message: "accessibility_action requires an action this companion supports — none was set, "
          + "or the client sent one added after this companion was built")
    }
  }

  // MARK: - Drag

  private static func dragAction(request: Idb_AccessibilityActionRequest, drag: Idb_AccessibilityActionRequest.Drag) throws -> Action {
    guard let source = try targetedQuery(from: request) else {
      throw GRPCStatus(code: .invalidArgument, message: "accessibility_action drag requires a marker or point source")
    }
    guard let destination = try dragDestination(drag) else {
      throw GRPCStatus(code: .invalidArgument, message: "accessibility_action drag requires a marker or point destination")
    }
    guard source != destination else {
      throw GRPCStatus(code: .invalidArgument, message: "accessibility_action drag source and destination are the same element")
    }
    let options = try dragOptions(drag)
    if case let .point(from) = source, case let .point(to) = destination {
      // Only checkable for two coordinates; a marker endpoint is resolved by the backend. A delta at
      // or above the distance samples the path once, which iOS reads as a flick rather than a drag.
      let distance = hypot(to.x - from.x, to.y - from.y)
      guard options.delta < Double(distance) else {
        throw GRPCStatus(
          code: .invalidArgument,
          message: "accessibility_action drag delta (\(options.delta)) must be smaller than the distance dragged (\(distance))")
      }
    }
    return .drag(source: source, destination: destination, options: options)
  }

  private static func dragDestination(_ drag: Idb_AccessibilityActionRequest.Drag) throws -> FBAccessibilityElementQuery? {
    switch drag.destination {
    case let .marker(marker):
      return .marker(
        value: marker, key: try searchableKey(from: drag.destinationMatchKey), depth: UInt(drag.destinationDepth))
    case let .point(point):
      return .point(CGPoint(x: point.x, y: point.y))
    case .none:
      return nil
    }
  }

  /// The wire's zero value means "server default", the same rule the swipe and pinch fields follow —
  /// a proto3 scalar cannot distinguish unset from zero, and none of these are useful at zero.
  private static func dragOptions(_ drag: Idb_AccessibilityActionRequest.Drag) throws -> FBDragOptions {
    let defaults = FBDragOptions()
    for (name, value) in [
      ("press_duration", drag.pressDuration), ("duration", drag.duration),
      ("release_duration", drag.releaseDuration), ("delta", drag.delta),
    ] where value < 0 {
      throw GRPCStatus(code: .invalidArgument, message: "accessibility_action drag \(name) must not be negative, got \(value)")
    }
    return FBDragOptions(
      pressDuration: drag.pressDuration > 0 ? drag.pressDuration : defaults.pressDuration,
      duration: drag.duration > 0 ? drag.duration : defaults.duration,
      releaseDuration: drag.releaseDuration > 0 ? drag.releaseDuration : defaults.releaseDuration,
      delta: drag.delta > 0 ? drag.delta : defaults.delta)
  }

  // MARK: - Targets

  private static func requiredQuery(from request: Idb_AccessibilityActionRequest, action: String) throws -> FBAccessibilityElementQuery {
    guard let query = try targetedQuery(from: request) else {
      throw GRPCStatus(code: .invalidArgument, message: "accessibility_action \(action) requires a marker or point target")
    }
    return query
  }

  // Returns nil when no target is set, which callers map to the frontmost app
  // (or reject, for actions that require an explicit element).
  private static func targetedQuery(from request: Idb_AccessibilityActionRequest) throws -> FBAccessibilityElementQuery? {
    switch request.target {
    case let .marker(marker):
      return .marker(
        value: marker, key: try searchableKey(from: request.matchKey), depth: UInt(request.depth))
    case let .point(point):
      return .point(CGPoint(x: point.x, y: point.y))
    case .none:
      return nil
    }
  }

  private static func scrollDirection(from direction: Idb_AccessibilityActionRequest.Scroll.Direction) throws -> FBAccessibilityScrollDirection {
    switch direction {
    case .up:
      return .up
    case .down:
      return .down
    case .left:
      return .left
    case .right:
      return .right
    case .visible:
      return .visible
    case .UNRECOGNIZED:
      throw GRPCStatus(code: .invalidArgument, message: "unknown scroll direction")
    }
  }

  private static func searchableKey(from key: Idb_AccessibilityActionRequest.SearchableKey) throws -> FBAXSearchableKey {
    switch key {
    case .label:
      return .label
    case .uniqueID:
      return .uniqueID
    case .value:
      return .value
    case .title:
      return .title
    case .role:
      return .role
    case .roleDescription:
      return .roleDescription
    case .subrole:
      return .subrole
    case .help:
      return .help
    case .placeholder:
      return .placeholder
    case .UNRECOGNIZED:
      throw GRPCStatus(code: .invalidArgument, message: "unrecognized accessibility key")
    }
  }
}
