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
    let configuration = try ScreenshotRequestTranslation.configuration(from: request)
    do {
      let result = try await commandExecutor.take_screenshot(configuration)
      return ScreenshotRequestTranslation.response(from: result)
    } catch let error as FBScreenshotGeometryError {
      // The crop is resolved against the screen that was actually captured, so a rect that
      // overhangs it can only be discovered here, once the target has been asked.
      throw ScreenshotRequestTranslation.status(for: error)
    } catch let error as FBScreenshotRenderError {
      // Otherwise a failed crop, scale or encode reaches the caller as an UNKNOWN with no message.
      throw ScreenshotRequestTranslation.status(for: error)
    }
  }
}
