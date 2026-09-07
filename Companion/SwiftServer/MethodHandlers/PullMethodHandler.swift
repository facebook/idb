/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import FBSimulatorControl
import Foundation
import GRPC
import IDBGRPCSwift

struct PullMethodHandler {

  let target: FBiOSTarget
  let commandExecutor: FBIDBCommandExecutor

  /// Human byte count for transfer summaries (e.g. "512 B", "1.5 KB").
  static func formatBytes(_ bytes: Int) -> String {
    let value = Double(bytes)
    switch value {
    case ..<1024:
      return "\(bytes) B"
    case ..<(1024 * 1024):
      return String(format: "%.1f KB", value / 1024)
    case ..<(1024 * 1024 * 1024):
      return String(format: "%.1f MB", value / (1024 * 1024))
    default:
      return String(format: "%.1f GB", value / (1024 * 1024 * 1024))
    }
  }

  func handle(request: Idb_PullRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_PullResponse>, context: GRPCAsyncServerCallContext) async throws {
    if request.dstPath.isEmpty {
      try await sendRawData(request: request, responseStream: responseStream)
    } else {
      try await sendFilePath(request: request, responseStream: responseStream)
    }
  }

  private func sendRawData(request: Idb_PullRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_PullResponse>) async throws {
    let logger = target.logger
    let path = request.srcPath as NSString
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)
    let url = commandExecutor.temporaryDirectory.temporaryDirectory()
    let tempPath = url.appendingPathComponent(path.lastPathComponent).path

    let filePath = try await commandExecutor.pull_file_path(
      request.srcPath,
      destination_path: tempPath,
      containerType: fileContainer)

    let archive = try await FBArchiveOperations.createGzippedTarAsync(forPath: filePath, logger: logger)

    var totalBytes = 0
    do {
      try await FileDrainWriter.performDrain(task: archive) { data in
        totalBytes += data.count
        let response = Idb_PullResponse.with { $0.payload.data = data }
        try await responseStream.send(response)
      }
    } catch {
      logger.info().log("pull failed after streaming \(Self.formatBytes(totalBytes))")
      throw error
    }
    logger.info().log("pull streamed \(Self.formatBytes(totalBytes))")
  }

  private func sendFilePath(request: Idb_PullRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_PullResponse>) async throws {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)

    let filePath = try await commandExecutor.pull_file_path(
      request.srcPath,
      destination_path: request.dstPath,
      containerType: fileContainer)
    let response = Idb_PullResponse.with {
      $0.payload = .with { $0.source = .filePath(filePath) }
    }
    try await responseStream.send(response)
    if let byteCount = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? NSNumber)?.intValue {
      target.logger.info().log("pull saved \(Self.formatBytes(byteCount)) to \(request.dstPath)")
    }
  }
}
