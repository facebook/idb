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
import IDBCompanionUtilities
import IDBGRPCSwift

struct ReplMethodHandler {

  let commandExecutor: FBIDBCommandExecutor
  let targetLogger: FBControlCoreLogger

  func handle(requestStream: GRPCAsyncRequestStream<Idb_ReplRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_ReplResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard case let .start(start) = try await requestStream.requiredNext.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "repl expected a Start message at the beginning of the stream") }

    // Launch the test bundle in REPL mode: libRepl injected, TestRepl/start
    // forced, and IDB_REPL_SOCKET_PATH set so the shim binds the control socket.
    let session = try await commandExecutor.repl_start(bundlePath: start.testBundlePath)

    // Per-session scratch directory for the dylibs received over the wire. It
    // lives on the host filesystem, which the simulator's test process can read.
    let scratchDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent("idb_repl_\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: scratchDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: scratchDirectory) }

    // Connect to the shim's control socket. It appears once the test process has
    // launched, so retry for a while.
    let client = try await ReplSocketClient.connect(path: session.socketPath, timeout: 120)
    defer { client.close() }

    targetLogger.debug().log("REPL session ready on socket \(session.socketPath)")
    try await responseStream.send(.with { $0.event = .ready(.init()) })

    var runIndex = 0
    bridge: for try await request in requestStream {
      switch request.control {
      case .start:
        throw GRPCStatus(code: .failedPrecondition, message: "repl session already started")

      case let .execute(execute):
        let dylibPath = (scratchDirectory as NSString).appendingPathComponent("run-\(runIndex).dylib")
        runIndex += 1
        try execute.dylib.write(to: URL(fileURLWithPath: dylibPath))

        let result = try await client.execute(dylibPath: dylibPath, symbol: execute.symbol)
        try await responseStream.send(
          .with {
            $0.event = .result(
              .with {
                $0.success = result.success
                $0.output = result.output
              })
          })

      case .stop, .none:
        break bridge
      }
    }

    // Closing the socket ends the shim's accept loop, so the test process exits;
    // wait for it (bounded), then report the session stopped.
    client.close()
    let thirtySeconds: UInt64 = 30 * 1_000_000_000
    try? await Task.timeout(nanoseconds: thirtySeconds) {
      try await bridgeFBFutureVoid(session.run)
    }
    try await responseStream.send(.with { $0.event = .stopped(.with { $0.desc = "REPL session ended" }) })
  }
}
