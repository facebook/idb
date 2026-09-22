/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import GRPCCore
import IDBGRPCSwift

struct HingeAngleMethodHandler {
  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_HingeAngleRequest, context: ServerContext) async throws -> Idb_HingeAngleResponse {
    let angle = try await commandExecutor.hinge_angle()
    return .with { $0.angle = angle }
  }
}
