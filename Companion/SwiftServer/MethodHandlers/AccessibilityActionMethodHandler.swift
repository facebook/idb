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
    case .none:
      throw GRPCStatus(code: .invalidArgument, message: "accessibility_action requires an action")
    }
    return .init()
  }

  private func performTap(request: Idb_AccessibilityActionRequest, tap: Idb_AccessibilityActionRequest.Tap) async throws {
    let query: FBAccessibilityElementQuery
    switch request.target {
    case let .marker(marker):
      query = .marker(
        value: marker, key: searchableKey(from: request.matchKey), depth: UInt(request.depth))
    case let .point(point):
      query = .point(CGPoint(x: point.x, y: point.y))
    case .none:
      throw GRPCStatus(code: .invalidArgument, message: "accessibility_action tap requires a marker or point target")
    }
    let expectedValue = tap.checkExpectedValue ? tap.expectedValue : nil
    try await commandExecutor.accessibility_tap(
      query: query,
      expectedValue: expectedValue,
      expectedKey: searchableKey(from: tap.expectedKey))
  }

  private func searchableKey(from key: Idb_AccessibilityActionRequest.SearchableKey) -> FBAXSearchableKey {
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
      return .label
    }
  }
}
