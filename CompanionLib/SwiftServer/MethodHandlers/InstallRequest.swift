/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPCCore
import IDBGRPCSwift

/// Where an install request's artifact comes from.
enum InstallPayload {
  /// Bytes streamed by the client: the first frame, then every frame after it. `rest` throws if the request stream does.
  case data(head: Data, rest: AsyncThrowingStream<Data, any Error>)
  case url(URL)
  case filePath(String)

  var kind: InstallPayloadKind {
    switch self {
    case .data:
      return .data
    case .url:
      return .url
    case .filePath:
      return .filePath
    }
  }
}

/// An install request, read once from its stream: the options before the payload, then the payload.
struct InstallRequest {
  var header: InstallHeader
  var payload: InstallPayload

  static func read(_ requests: RequestStreamReader<Idb_InstallRequest>) async throws -> InstallRequest {
    let header = try await InstallHeader.read { try await requests.requiredNext() }
    let payload: InstallPayload
    switch header.payload.source {
    case let .data(head):
      payload = .data(head: head, rest: dataFrames(after: requests))
    case let .url(string):
      guard let url = URL(string: string) else {
        throw RPCError(code: .invalidArgument, message: "Invalid url source")
      }
      payload = .url(url)
    case let .filePath(path):
      payload = .filePath(path)
    case .compression, nil:
      throw RPCError(code: .invalidArgument, message: "Incorrect payload source")
    }
    return InstallRequest(header: header, payload: payload)
  }

  /// The data in every remaining frame, skipping any that carry none.
  private static func dataFrames(after requests: RequestStreamReader<Idb_InstallRequest>) -> AsyncThrowingStream<Data, any Error> {
    AsyncThrowingStream {
      while let request = try await requests.next() {
        if let data = request.extractDataFrame() {
          return data
        }
      }
      return nil
    }
  }
}
