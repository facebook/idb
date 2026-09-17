/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore
import IDBGRPCSwift

struct AddMediaMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(requestStream: RequestStreamReader<Idb_AddMediaRequest>, context: ServerContext) async throws -> Idb_AddMediaResponse {
    try await MultisourceFileReader.withFilePathURLs(from: requestStream, temporaryDirectory: commandExecutor.temporaryDirectory, extractFromSubdir: true) { extractedFileURLs in
      try await commandExecutor.add_media(extractedFileURLs)
    }
    return .init()
  }
}
