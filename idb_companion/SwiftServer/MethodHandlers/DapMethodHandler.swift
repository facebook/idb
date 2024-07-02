/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import FBSimulatorControl
import GRPC
import IDBCompanionUtilities
import IDBGRPCSwift

struct DapMethodHandler {

  let commandExecutor: FBIDBCommandExecutor
  let targetLogger: FBControlCoreLogger

  func handle(requestStream: GRPCAsyncRequestStream<Idb_DapRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_DapResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard case let .start(start) = try await requestStream.requiredNext.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "Dap command expected a Start messaged in the beginning of the Stream") }

    let writer = FBProcessInput<FBDataConsumer>.fromConsumer() as! FBProcessInput<AnyObject>
    let dapProcess = try await startDapServer(startRequest: start, processInput: writer, responseStream: responseStream)

    let tenHours: UInt64 = 36000 * 1000000000
    try await Task.timeout(nanoseconds: tenHours) {
      try await consumeElements(from: requestStream, to: writer, dapProcess: dapProcess)
    }

    let stoppedResponse = Idb_DapResponse.with {
      $0.event = .stopped(
        .with { $0.desc = "Dap server stopped" }
      )
    }
    try await responseStream.send(stoppedResponse)
  }

  private func startDapServer(startRequest: Idb_DapRequest.Start, processInput: FBProcessInput<AnyObject>, responseStream: GRPCAsyncResponseStreamWriter<Idb_DapResponse>) async throws -> FBProcess<AnyObject, FBDataConsumer, NSString> {

    let lldbVSCode = "dap/\(startRequest.debuggerPkgID)/usr/bin/lldb-vscode"

    let stdOutConsumer = createDataConsumer(to: responseStream)
    targetLogger.debug().log("Starting dap server with path \(lldbVSCode)")

    let tenMinutes: UInt64 = 600 * 1000000000
    let process = try await Task.timeout(nanoseconds: tenMinutes) {
      try await BridgeFuture.value(commandExecutor.dapServer(withPath: lldbVSCode, stdIn: processInput, stdOut: stdOutConsumer))
    }

    targetLogger.debug().log("Dap server spawn with PID: \(process.processIdentifier)")
    let serverStartedResponse = Idb_DapResponse.with {
      $0.event = .started(.init())
    }
    try await responseStream.send(serverStartedResponse)

    return process
  }

  private func consumeElements(from requestStream: GRPCAsyncRequestStream<Idb_DapRequest>, to writer: FBProcessInput<AnyObject>, dapProcess: FBProcess<AnyObject, FBDataConsumer, NSString>) async throws {
    for try await request in requestStream {
      switch request.control {
      case .start:
        throw GRPCStatus(code: .failedPrecondition, message: "DAP server already started")

      case .none:
        throw GRPCStatus(code: .invalidArgument, message: "Empty control in request")

      case let .pipe(pipe):
        guard !pipe.data.isEmpty else {
          targetLogger.debug().log("Dap request received empty message. Transmission finished")
          return
        }
        targetLogger.debug().log("Dap Request. Received \(pipe.data.count) bytes from client")
        writer.contents.consumeData(pipe.data)

      case .stop:
        targetLogger.debug().log("Received stop from Dap Request")
        targetLogger.debug().log("Stopping dap server with pid \(dapProcess.processIdentifier). Stderr: \(dapProcess.stdErr ?? "Empty")")
        return
      }
    }
  }

  private func createDataConsumer(to responseStream: GRPCAsyncResponseStreamWriter<Idb_DapResponse>) -> FBDataConsumer {
    let responseWriter = FIFOStreamWriter(stream: responseStream)

    return FBBlockDataConsumer.synchronousDataConsumer { data in
      let response = Idb_DapResponse.with {
        $0.event = .stdout(
          .with { $0.data = data }
        )
      }
      do {
        try responseWriter.send(response)
        targetLogger.debug().log("Dap server stdout consumer: sent \(data.count) bytes.")
      } catch {
        targetLogger.debug().log("Dap server stdout consumer: error \(error) when tried to send bytes.")
      }
    }
  }
}
