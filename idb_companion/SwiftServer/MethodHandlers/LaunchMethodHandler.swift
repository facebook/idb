/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import Foundation
import GRPC
import IDBCompanionUtilities
import IDBGRPCSwift

struct LaunchMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(requestStream: GRPCAsyncRequestStream<Idb_LaunchRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_LaunchResponse>, context: GRPCAsyncServerCallContext) async throws {
    var completions: [FBFuture<NSNull>] = []

    var request = try await requestStream.requiredNext
    guard case let .start(start) = request.control else {
      throw GRPCStatus(code: .failedPrecondition, message: "Application not started yet")
    }
    var stdOut = processOutputForNullDevice()
    var stdErr = processOutputForNullDevice()

    let responseWriter = FIFOStreamWriter(stream: responseStream)
    if start.waitFor {
      let stdOutConsumer = pipeOutput(interface: .stdout, responseWriter: responseWriter)
      completions.append(stdOutConsumer.finishedConsuming)
      stdOut = FBProcessOutput<AnyObject>(for: stdOutConsumer)

      let stdErrConsumer = pipeOutput(interface: .stderr, responseWriter: responseWriter)
      completions.append(stdErrConsumer.finishedConsuming)
      stdErr = FBProcessOutput<AnyObject>(for: stdErrConsumer)
    }
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: nil, stdOut: stdOut, stdErr: stdErr)
    let config = FBApplicationLaunchConfiguration(bundleID: start.bundleID,
                                                  bundleName: nil,
                                                  arguments: start.appArgs,
                                                  environment: start.env,
                                                  waitForDebugger: start.waitForDebugger,
                                                  io: io,
                                                  launchMode: start.foregroundIfRunning ? .foregroundIfRunning : .failIfRunning)
    let launchedApp = try await BridgeFuture.value(commandExecutor.launch_app(config))
    let response = Idb_LaunchResponse.with {
      $0.debugger.pid = UInt64(launchedApp.processIdentifier)
    }
    try await responseStream.send(response)

    guard start.waitFor else { return }

    request = try await requestStream.requiredNext
    guard case .stop = request.control else {
      throw GRPCStatus(code: .failedPrecondition, message: "Application has already started")
    }

    try await BridgeFuture.await(launchedApp.applicationTerminated.cancel())

    _ = try await BridgeFuture.values(completions)
  }

  private func processOutputForNullDevice() -> FBProcessOutput<AnyObject> {
    return FBProcessOutput<AnyObject>.forNullDevice() as! FBProcessOutput<AnyObject>
  }

  private func pipeOutput(interface: Idb_ProcessOutput.Interface, responseWriter: FIFOStreamWriter<GRPCAsyncResponseStreamWriter<Idb_LaunchResponse>>) -> (FBDataConsumer & FBDataConsumerLifecycle) {
    return FBBlockDataConsumer.asynchronousDataConsumer { data in
      let response = Idb_LaunchResponse.with {
        $0.output.data = data
        $0.output.interface = interface
      }
      try? responseWriter.send(response)
    }
  }
}
