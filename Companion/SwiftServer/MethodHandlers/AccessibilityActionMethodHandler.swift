/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import FBSimulatorControl
import Foundation
import GRPC
import IDBGRPCSwift

struct AccessibilityActionMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_AccessibilityActionRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_AccessibilityActionResponse {
    switch try AccessibilityActionRequestTranslation.action(from: request) {
    case let .tap(query, expectedValue, expectedKey):
      try await commandExecutor.accessibility_tap(query: query, expectedValue: expectedValue, expectedKey: expectedKey)
    case let .scroll(query, direction):
      try await commandExecutor.accessibility_scroll(query: query, direction: direction)
    case let .setValue(query, value):
      try await commandExecutor.accessibility_set_value(query: query, value: value)
    case let .drag(source, destination, options):
      try await commandExecutor.accessibility_drag(from: source, to: destination, options: options)
    }
    return .init()
  }
}
