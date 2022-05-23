/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import IDBGRPCSwift
import GRPC
import FBControlCore

struct DebugserverMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(requestStream: GRPCAsyncRequestStream<Idb_DebugServerRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_DebugServerResponse>, context: GRPCAsyncServerCallContext) async throws {

    for try await request in requestStream {
      switch request.control {
      case let .start(start):
        let debugServer = try await BridgeFuture.value(commandExecutor.debugserver_start(start.bundleID))
        try await responseStream.send(debugserverStatusToProto(debugServer: debugServer))

      case .status:
        let debugServer = try await BridgeFuture.value(commandExecutor.debugserver_status())
        try await responseStream.send(debugserverStatusToProto(debugServer: debugServer))

      case .stop:
        let debugServer = try await BridgeFuture.value(commandExecutor.debugserver_stop())
        try await responseStream.send(debugserverStatusToProto(debugServer: debugServer))
        return

      case .pipe:
        throw GRPCStatus(code: .unimplemented)

      case .none:
        throw GRPCStatus(code: .invalidArgument, message: "Received empty control")
      }
    }
  }

  private func debugserverStatusToProto(debugServer: FBDebugServer) -> Idb_DebugServerResponse {
    return .with {
      $0.status = .with {
        $0.lldbBootstrapCommands = debugServer.lldbBootstrapCommands
      }
    }
  }

}
