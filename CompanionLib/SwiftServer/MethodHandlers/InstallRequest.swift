/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBArtifactStaging
import FBControlCore
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

/// The options an install request stream carries before its payload.
struct InstallHeader: Equatable {
  var destination: Idb_InstallRequest.Destination
  var nameHint: String?
  var makeDebuggable = false
  var overrideModificationTime = false
  var skipSigningBundles = false
  var linkDsymToBundle: Idb_InstallRequest.LinkDsymToBundle?
  var compression = CompressionFormat.GZIP
  /// The first payload frame. A data payload continues in the frames after it.
  var payload: Idb_Payload

  static func read(from next: () async throws -> Idb_InstallRequest) async throws -> InstallHeader {
    let request = try await next()
    guard case let .destination(destination) = request.value else {
      throw RPCError(code: .failedPrecondition, message: "Expected destination as first request in stream")
    }
    var header = InstallHeader(destination: destination, payload: Idb_Payload())
    var seen: Set = ["destination"]
    // Options and the compression frame may come in any order, each at most once, until the first payload.
    while true {
      let frame = try await next()
      let option: String
      switch frame.value {
      case let .nameHint(value):
        option = "name_hint"
        header.nameHint = value
      case let .makeDebuggable(value):
        option = "make_debuggable"
        header.makeDebuggable = value
      case let .overrideModificationTime(value):
        option = "override_modification_time"
        header.overrideModificationTime = value
      case let .skipSigningBundles(value):
        option = "skip_signing_bundles"
        header.skipSigningBundles = value
      case let .linkDsymToBundle(value):
        option = "link_dsym_to_bundle"
        header.linkDsymToBundle = value
      case let .payload(payload):
        guard case let .compression(format) = payload.source else {
          header.payload = payload
          return header
        }
        option = "compression"
        header.compression = CompressionFormat(format)
      case .destination:
        option = "destination"
      case nil:
        throw RPCError(code: .invalidArgument, message: "Expected the next item in the stream to be a payload")
      }
      guard seen.insert(option).inserted else {
        throw RPCError(code: .invalidArgument, message: "Repeated \(option) in install request stream")
      }
    }
  }
}
