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
import ReplProtocol

struct ReplMethodHandler {

  let commandExecutor: FBIDBCommandExecutor
  let targetLogger: FBControlCoreLogger

  func handle(requestStream: GRPCAsyncRequestStream<Idb_ReplRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_ReplResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard case let .start(start) = try await requestStream.requiredNext.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "repl expected a Start message at the beginning of the stream") }

    targetLogger.debug().log("REPL session context: \(start.context)")

    let session: ReplSession
    if case .test = start.context {
      session = try await commandExecutor.repl_start_test(bundlePath: start.testBundlePath)
    } else {
      session = try await commandExecutor.repl_start_simulator()
    }

    try await serve(session: session, requestStream: requestStream, responseStream: responseStream)
  }

  /// Bridges the gRPC repl stream to a launched session's control socket:
  /// connects to the socket, reports `ready`, forwards each `Execute` (a dylib
  /// plus a symbol) to the socket and streams back the result, and on stop/EOF
  /// closes the socket (which ends the served process) and reports `stopped`.
  private func serve(session: ReplSession, requestStream: GRPCAsyncRequestStream<Idb_ReplRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_ReplResponse>) async throws {
    // Per-session scratch directory for the dylibs received over the wire. It
    // lives on the host filesystem, which the simulator process can read.
    let scratchDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent("idb_repl_\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: scratchDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: scratchDirectory) }

    // Connect to the control socket. It appears once the launched process binds
    // it, so retry for a while.
    let client = try await ReplSocketClient.connect(path: session.socketPath, timeout: 120)
    defer { client.close() }

    // The host greets us with the .swiftinterface paths it generated in-process
    // (empty in the simulator context). Combine them with the session's pre-built
    // interfaces (the `IDB` module's). We read each file's contents here and
    // forward those (not the paths) to the driver, which may not share a
    // filesystem with the companion; the driver materializes them locally.
    let interfacePaths = try await client.readGreeting() + session.extraInterfacePaths
    let generatedInterfaces: [Idb_ReplResponse.Ready.GeneratedInterface] = interfacePaths.compactMap { path in
      guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
        targetLogger.error().log("Failed to read generated interface at \(path); skipping")
        return nil
      }
      let moduleName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
      return .with {
        $0.moduleName = moduleName
        $0.contents = contents
      }
    }

    targetLogger.debug().log("REPL session ready on socket \(session.socketPath)")
    try await responseStream.send(
      .with {
        $0.event = .ready(
          .with {
            $0.deviceType = commandExecutor.replDeviceType
            $0.generatedInterfaces = generatedInterfaces
          })
      })

    // Services nested `host_command`s the served process sends back while an
    // execute is running (e.g. `IDB.tap`), mapping them to FBIDBCommandExecutor.
    let dispatcher = HostCommandDispatcher(commandExecutor: commandExecutor)

    var runIndex = 0
    bridge: for try await request in requestStream {
      switch request.control {
      case .start:
        throw GRPCStatus(code: .failedPrecondition, message: "repl session already started")

      case let .execute(execute):
        let dylibPath = (scratchDirectory as NSString).appendingPathComponent("run-\(runIndex).dylib")
        runIndex += 1
        try execute.dylib.write(to: URL(fileURLWithPath: dylibPath))

        let result = try await client.execute(
          dylibPath: dylibPath,
          symbol: execute.symbol,
          hostCommandHandler: { commandData in
            guard let command = try? PropertyListDecoder().decode(ReplCommand.self, from: commandData) else {
              return .failure(HostCommandError.message("repl: could not decode host command"))
            }
            return await dispatcher.run(command)
          })
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

    // Closing the socket ends the served process's accept loop, so it exits;
    // wait for it (bounded), then report the session stopped.
    client.close()
    let thirtySeconds: UInt64 = 30 * 1_000_000_000
    nonisolated(unsafe) let session = session
    try? await Task.timeout(nanoseconds: thirtySeconds) {
      try await bridgeFBFutureVoid(session.run)
    }
    try await responseStream.send(.with { $0.event = .stopped(.with { $0.desc = "REPL session ended" }) })
  }
}
