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

struct AddMediaMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(requestStream: GRPCAsyncRequestStream<Idb_AddMediaRequest>, context: GRPCAsyncServerCallContext) async throws -> Idb_AddMediaResponse {
    // grpc-swift traps if a second AsyncIterator is created; read every
    // request frame through one owned iterator.
    let stream = SingleIteratorRequestStream(requestStream)

    let extractedFileURLs =
      try await MultisourceFileReader
      .filePathURLs(from: stream, temporaryDirectory: commandExecutor.temporaryDirectory, extractFromSubdir: true)

    try await commandExecutor.add_media(extractedFileURLs)
    return .init()
  }
}
