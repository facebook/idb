/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import GRPC
import IDBGRPCSwift

struct ScreenshotMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_ScreenshotRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ScreenshotResponse {
    let screenshot = try await commandExecutor.take_screenshot(.png)
    return .with {
      $0.imageData = screenshot
    }
  }
}
