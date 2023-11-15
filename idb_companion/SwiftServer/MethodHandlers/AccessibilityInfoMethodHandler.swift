/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import Foundation
import GRPC
import IDBGRPCSwift

struct AccessibilityInfoMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_AccessibilityInfoRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_AccessibilityInfoResponse {
    var point: NSValue?
    if request.hasPoint {
      point = NSValue(point: .init(x: request.point.x, y: request.point.y))
    }
    let nested = request.format == .nested
    let info = try await BridgeFuture.value(commandExecutor.accessibility_info_(at_point: point, nestedFormat: nested))
    let jsonData = try JSONSerialization.data(withJSONObject: info)
    return .with {
      $0.json = String(data: jsonData, encoding: .utf8) ?? ""
    }
  }
}
