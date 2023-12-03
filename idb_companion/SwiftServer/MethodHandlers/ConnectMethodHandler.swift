/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import Foundation
import GRPC
import IDBGRPCSwift

struct ConnectMethodHandler {

  let reporter: FBEventReporter
  let logger: FBIDBLogger
  let target: FBiOSTarget

  func handle(request: Idb_ConnectRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ConnectResponse {
    self.reporter.addMetadata(request.metadata)
    let isLocal = FileManager.default.fileExists(atPath: request.localFilePath)

    return Idb_ConnectResponse.with {
      $0.companion = .with {
        $0.udid = target.udid
        $0.isLocal = isLocal

        do {
          $0.metadata = try JSONSerialization.data(withJSONObject: reporter.metadata, options: [])
        } catch {
          logger.error().log("Error while serializing metadata \(error.localizedDescription)")
        }
      }
    }
  }
}
