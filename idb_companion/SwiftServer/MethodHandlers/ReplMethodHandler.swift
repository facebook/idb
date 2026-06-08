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

    targetLogger.debug().log("REPL session context: \(start.context)")

    if case .test = start.context {
      try await handleTest(start: start, requestStream: requestStream, responseStream: responseStream)
    } else {
      try await handleSimulator(responseStream: responseStream)
    }
  }

  /// The `test` context: launch the test bundle in REPL mode (libRepl injected,
  /// TestRepl/start forced, IDB_REPL_SOCKET_PATH set), connect to the shim's
  /// control socket, and bridge Execute messages to it.
  private func handleTest(start: Idb_ReplRequest.Start, requestStream: GRPCAsyncRequestStream<Idb_ReplRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_ReplResponse>) async throws {
    let session = try await commandExecutor.repl_start_test(bundlePath: start.testBundlePath)

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

  /// The `simulator` context: launch SimulatorFrameworkBridge on the simulator.
  private func handleSimulator(responseStream: GRPCAsyncResponseStreamWriter<Idb_ReplResponse>) async throws {
    try await commandExecutor.repl_start_simulator()
    targetLogger.debug().log("SimulatorFrameworkBridge launched for REPL simulator context")

    // The bridge does not host a control socket yet, so there is nothing to
    // bridge. Report ready, then end the session.
    try await responseStream.send(.with { $0.event = .ready(.init()) })
    try await responseStream.send(.with { $0.event = .stopped(.with { $0.desc = "REPL simulator session ended" }) })
  }
}
