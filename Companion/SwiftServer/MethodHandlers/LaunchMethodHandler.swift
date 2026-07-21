/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import CompanionUtilities
import FBControlCore
import Foundation
import GRPC
import IDBGRPCSwift

struct LaunchMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(requestStream: GRPCAsyncRequestStream<Idb_LaunchRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_LaunchResponse>, context: GRPCAsyncServerCallContext) async throws {
    var consumers: [any FBDataConsumerLifecycle] = []

    var request = try await requestStream.requiredNext
    guard case let .start(start) = request.control else {
      throw GRPCStatus(code: .failedPrecondition, message: "Application not started yet")
    }
    var stdOut = processOutputForNullDevice()
    var stdErr = processOutputForNullDevice()

    let responseWriter = FIFOStreamWriter(stream: responseStream)
    if start.waitFor {
      let stdOutConsumer = pipeOutput(interface: .stdout, responseWriter: responseWriter)
      consumers.append(stdOutConsumer)
      stdOut = FBProcessOutput<AnyObject>(for: stdOutConsumer)

      let stdErrConsumer = pipeOutput(interface: .stderr, responseWriter: responseWriter)
      consumers.append(stdErrConsumer)
      stdErr = FBProcessOutput<AnyObject>(for: stdErrConsumer)
    }
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: nil, stdOut: stdOut, stdErr: stdErr)

    var environment = start.env
    var launchMode: FBApplicationLaunchMode = start.foregroundIfRunning ? .foregroundIfRunning : .failIfRunning
    if start.enableRepl {
      // Setup the launch for the REPL (inject libRepl + the IDB_REPL_* vars) and
      // force a relaunch so an already-running, un-injected app picks up the dylib.
      let replEnvironment = try await commandExecutor.replAppLaunchEnvironment(bundleID: start.bundleID)
      for (key, value) in replEnvironment {
        if key == "DYLD_INSERT_LIBRARIES", let existing = environment[key], !existing.isEmpty {
          environment[key] = "\(existing):\(value)"
        } else {
          environment[key] = value
        }
      }
      launchMode = .relaunchIfRunning
    }

    let config = FBApplicationLaunchConfiguration(
      bundleID: start.bundleID,
      bundleName: nil,
      arguments: start.appArgs,
      environment: environment,
      waitForDebugger: start.waitForDebugger,
      io: io,
      launchMode: launchMode)
    let launchedApp = try await commandExecutor.launch_app(config)
    let response = Idb_LaunchResponse.with {
      $0.debugger.pid = UInt64(launchedApp.processIdentifier)
    }
    try await responseStream.send(response)

    guard start.waitFor else { return }

    request = try await requestStream.requiredNext
    guard case .stop = request.control else {
      throw GRPCStatus(code: .failedPrecondition, message: "Application has already started")
    }

    try await launchedApp.terminate()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for consumer in consumers {
        group.addTask {
          try await consumer.awaitFinishedConsumingAsync()
        }
      }
      try await group.waitForAll()
    }
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
