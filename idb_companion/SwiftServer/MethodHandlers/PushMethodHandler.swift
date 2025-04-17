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

struct PushMethodHandler {

  let target: FBiOSTarget
  let commandExecutor: FBIDBCommandExecutor

  func handle(requestStream: GRPCAsyncRequestStream<Idb_PushRequest>, context: GRPCAsyncServerCallContext) async throws -> Idb_PushResponse {
    let request = try await requestStream.requiredNext

    guard case let .inner(inner) = request.value
    else { throw GRPCStatus(code: .invalidArgument, message: "Expected inner as first request in stream") }

    let extractedFileURLs =
      try await MultisourceFileReader
      .filePathURLs(from: requestStream, temporaryDirectory: commandExecutor.temporaryDirectory, extractFromSubdir: false)

    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: inner.container)
    try await BridgeFuture.await(
      commandExecutor.push_files(extractedFileURLs, to_path: inner.dstPath, containerType: fileContainer)
    )

    return .init()
  }
}
