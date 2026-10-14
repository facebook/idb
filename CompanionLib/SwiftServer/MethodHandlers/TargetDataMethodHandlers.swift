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
      try await commandExecutor.addMedia(extractedFileURLs)
    }
    return .init()
  }
}

struct ContactsUpdateMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_ContactsUpdateRequest, context: ServerContext) async throws -> Idb_ContactsUpdateResponse {
    try await commandExecutor.updateContacts(request.payload.data)
    return .init()
  }
}

struct ClearKeychainMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_ClearKeychainRequest, context: ServerContext) async throws -> Idb_ClearKeychainResponse {
    try await commandExecutor.clearKeychain()
    return .init()
  }
}
