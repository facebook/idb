/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import GRPCCore
import IDBGRPCSwift

struct LsMethodHandler {

  let commandExecutor: IDBCommandExecutor

  /// One-line result summary for the completion log, so directory listings
  /// report how much they returned without dumping the entries.
  static func summarize(_ response: Idb_LsResponse) -> String {
    let count = response.files.count + response.listings.reduce(0) { $0 + $1.files.count }
    return count == 1 ? "1 entry" : "\(count) entries"
  }

  func handle(request: Idb_LsRequest, context: ServerContext) async throws -> Idb_LsResponse {
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

struct MkdirMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_MkdirRequest, context: ServerContext) async throws -> Idb_MkdirResponse {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)
    try await commandExecutor.create_directory(request.path, containerType: fileContainer)
    return .init()
  }
}

struct MvMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_MvRequest, context: ServerContext) async throws -> Idb_MvResponse {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)
    try await commandExecutor.move_paths(request.srcPaths, to_path: request.dstPath, containerType: fileContainer)
    return .init()
  }
}

struct RmMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_RmRequest, context: ServerContext) async throws -> Idb_RmResponse {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)
    try await commandExecutor.remove_paths(request.paths, containerType: fileContainer)
    return .init()
  }
}

struct PushMethodHandler {

  let target: any Target
  let commandExecutor: IDBCommandExecutor

  func handle(requestStream: RequestStreamReader<Idb_PushRequest>, context: ServerContext) async throws -> Idb_PushResponse {
    let request = try await requestStream.requiredNext()

    guard case let .inner(inner) = request.value
    else { throw RPCError(code: .invalidArgument, message: "Expected inner as first request in stream") }

    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: inner.container)
    try await MultisourceFileReader.withFilePathURLs(from: requestStream, temporaryDirectory: commandExecutor.temporaryDirectory, extractFromSubdir: false) { extractedFileURLs in
      try await commandExecutor.push_files(extractedFileURLs, to_path: inner.dstPath, containerType: fileContainer)
    }

    return .init()
  }
}
