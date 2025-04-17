/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBSimulatorControl
import Foundation
import GRPC
import IDBGRPCSwift

struct PullMethodHandler {

  let target: FBiOSTarget
  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_PullRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_PullResponse>, context: GRPCAsyncServerCallContext) async throws {
    if request.dstPath.isEmpty {
      try await sendRawData(request: request, responseStream: responseStream)
    } else {
      try await sendFilePath(request: request, responseStream: responseStream)
    }
  }

  private func sendRawData(request: Idb_PullRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_PullResponse>) async throws {
    guard let logger = target.logger else {
      throw GRPCStatus(code: .internalError, message: "Internal logger not configured")
    }
    let path = request.srcPath as NSString
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)
    let url = commandExecutor.temporaryDirectory.temporaryDirectory()
    let tempPath = url.appendingPathComponent(path.lastPathComponent).path

    let filePath = try await BridgeFuture.value(
      commandExecutor.pull_file_path(
        request.srcPath,
        destination_path: tempPath,
        containerType: fileContainer)
    )

    let archiveFuture = FBArchiveOperations.createGzippedTar(forPath: filePath as String, logger: logger)

    try await FileDrainWriter.performDrain(taskFuture: archiveFuture) { data in
      let response = Idb_PullResponse.with { $0.payload.data = data }
      try await responseStream.send(response)
    }
  }

  private func sendFilePath(request: Idb_PullRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_PullResponse>) async throws {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)

    let filePath =
      try await BridgeFuture.value(
        commandExecutor.pull_file_path(
          request.srcPath,
          destination_path: request.dstPath,
          containerType: fileContainer)
      ) as String
    let response = Idb_PullResponse.with {
      $0.payload = .with { $0.source = .filePath(filePath) }
    }
    try await responseStream.send(response)
  }
}
