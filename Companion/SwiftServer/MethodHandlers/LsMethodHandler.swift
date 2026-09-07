/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import Foundation
import GRPC
import IDBGRPCSwift

struct LsMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  /// One-line result summary for the completion log, so directory listings
  /// report how much they returned without dumping the entries.
  static func summarize(_ response: Idb_LsResponse) -> String {
    let count = response.files.count + response.listings.reduce(0) { $0 + $1.files.count }
    return count == 1 ? "1 entry" : "\(count) entries"
  }

  func handle(request: Idb_LsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_LsResponse {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)

    if request.paths.isEmpty {
      return try await list(path: request.path, fileContainer: fileContainer)
    } else {
      return try await list(pathList: request.paths, fileContainer: fileContainer)
    }
  }

  private func list(path: String, fileContainer: String) async throws -> Idb_LsResponse {
    let paths = try await commandExecutor.list_path(path, containerType: fileContainer)

    return .with {
      $0.files = paths.map(toFileInfo)
    }
  }

  private func list(pathList: [String], fileContainer: String) async throws -> Idb_LsResponse {
    let pathsToPaths = try await commandExecutor.list_paths(pathList, containerType: fileContainer)

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
