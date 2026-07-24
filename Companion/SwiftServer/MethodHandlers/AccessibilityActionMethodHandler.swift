/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import CoreGraphics
import FBControlCore
import FBSimulatorControl
import Foundation
import GRPC
import IDBGRPCSwift

struct AccessibilityActionMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_AccessibilityActionRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_AccessibilityActionResponse {
    switch request.action {
    case let .tap(tap):
      try await performTap(request: request, tap: tap)
    case let .scroll(scroll):
      try await performScroll(request: request, scroll: scroll)
    case .none:
      throw GRPCStatus(code: .invalidArgument, message: "accessibility_action requires an action")
    }
    return .init()
  }

  private func performTap(request: Idb_AccessibilityActionRequest, tap: Idb_AccessibilityActionRequest.Tap) async throws {
    guard let query = try targetedQuery(from: request) else {
      throw GRPCStatus(code: .invalidArgument, message: "accessibility_action tap requires a marker or point target")
    }
    let expectedValue = tap.checkExpectedValue ? tap.expectedValue : nil
    try await commandExecutor.accessibility_tap(
      query: query,
      expectedValue: expectedValue,
      expectedKey: try searchableKey(from: tap.expectedKey))
  }

  private func performScroll(request: Idb_AccessibilityActionRequest, scroll: Idb_AccessibilityActionRequest.Scroll) async throws {
    let query = try targetedQuery(from: request) ?? .frontmost
    let direction = try scrollDirection(from: scroll.direction)
    try await commandExecutor.accessibility_scroll(query: query, direction: direction)
  }

  // Returns nil when no target is set, which callers map to the frontmost app
  // (or reject, for actions that require an explicit element).
  private func targetedQuery(from request: Idb_AccessibilityActionRequest) throws -> FBAccessibilityElementQuery? {
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

  private func scrollDirection(from direction: Idb_AccessibilityActionRequest.Scroll.Direction) throws -> FBAccessibilityScrollDirection {
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

  private func searchableKey(from key: Idb_AccessibilityActionRequest.SearchableKey) throws -> FBAXSearchableKey {
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
