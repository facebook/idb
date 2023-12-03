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

struct LsMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_LsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_LsResponse {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)

    if request.paths.isEmpty {
      return try await list(path: request.path, fileContainer: fileContainer)
    } else {
      return try await list(pathList: request.paths, fileContainer: fileContainer)
    }
  }

  private func list(path: String, fileContainer: String) async throws -> Idb_LsResponse {
    let paths: [String] = try await BridgeFuture.value(commandExecutor.list_path(path, containerType: fileContainer))

    return .with {
      $0.files = paths.map(toFileInfo)
    }
  }

  private func list(pathList: [String], fileContainer: String) async throws -> Idb_LsResponse {
    let pathsToPaths: [String: [String]] = try await BridgeFuture.value(commandExecutor.list_paths(pathList, containerType: fileContainer))

    return .with {
      $0.listings = pathsToPaths.map { containerPath, paths in
        .with {
          $0.parent = .with {
            $0.path = containerPath
          }
          $0.files = paths.map(toFileInfo)
        }
      }
    }
  }

  private func toFileInfo(path: String) -> Idb_FileInfo {
    .with { $0.path = path }
  }
}
