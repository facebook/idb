/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore
import IDBGRPCSwift

/// The options an install request stream carries before its payload.
struct InstallHeader: Equatable {
  var destination: Idb_InstallRequest.Destination
  var nameHint: String?
  var makeDebuggable = false
  var overrideModificationTime = false
  var skipSigningBundles = false
  var linkDsymToBundle: Idb_InstallRequest.LinkDsymToBundle?
  var compression = FBCompressionFormat.GZIP
  /// The first payload frame. A data payload continues in the frames after it.
  var payload: Idb_Payload

  static func read(from next: () async throws -> Idb_InstallRequest) async throws -> InstallHeader {
    var request = try await next()
    guard case let .destination(destination) = request.value else {
      throw RPCError(code: .failedPrecondition, message: "Expected destination as first request in stream")
    }
    request = try await next()

    var nameHint: String?
    if case let .nameHint(value) = request.value {
      nameHint = value
      request = try await next()
    }
    var makeDebuggable = false
    if case let .makeDebuggable(value) = request.value {
      makeDebuggable = value
      request = try await next()
    }
    var overrideModificationTime = false
    if case let .overrideModificationTime(value) = request.value {
      overrideModificationTime = value
      request = try await next()
    }
    var skipSigningBundles = false
    if case let .skipSigningBundles(value) = request.value {
      skipSigningBundles = value
      request = try await next()
    }
    var linkDsymToBundle: Idb_InstallRequest.LinkDsymToBundle?
    if case let .linkDsymToBundle(value) = request.value {
      linkDsymToBundle = value
      request = try await next()
    }

    var payload = try requirePayload(request)
    var compression = FBCompressionFormat.GZIP
    if case let .compression(format) = payload.source {
      compression = FBCompressionFormat(format)
      payload = try requirePayload(try await next())
    }

    return InstallHeader(
      destination: destination,
      nameHint: nameHint,
      makeDebuggable: makeDebuggable,
      overrideModificationTime: overrideModificationTime,
      skipSigningBundles: skipSigningBundles,
      linkDsymToBundle: linkDsymToBundle,
      compression: compression,
      payload: payload)
  }

  private static func requirePayload(_ request: Idb_InstallRequest) throws -> Idb_Payload {
    guard let payload = request.extractPayload() else {
      throw RPCError(code: .invalidArgument, message: "Expected the next item in the stream to be a payload")
    }
    return payload
  }
}
