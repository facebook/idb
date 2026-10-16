/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import GRPCCore
import IDBConcurrency
import IDBGRPCSwift

struct LaunchMethodHandler: @unchecked Sendable {

  let target: CompanionTarget
  let commandExecutor: IDBCommandExecutor

  func handle(requestStream: RequestStreamReader<Idb_LaunchRequest>, responseStream: RPCWriter<Idb_LaunchResponse>, context: ServerContext) async throws {
    var consumers: [any DataConsumerLifecycle] = []

    var request = try await requestStream.requiredNext()
    guard case let .start(start) = request.control else {
      throw RPCError(code: .failedPrecondition, message: "Application not started yet")
    }
    var stdOut = ApplicationOutput.nullDevice
    var stdErr = ApplicationOutput.nullDevice

    let responseWriter = FIFOStreamWriter(stream: responseStream)
    if start.waitFor {
      let stdOutConsumer = Self.pipeOutput(interface: .stdout) { try responseWriter.send($0) }
      consumers.append(stdOutConsumer)
      stdOut = .consumer(stdOutConsumer)

      let stdErrConsumer = Self.pipeOutput(interface: .stderr) { try responseWriter.send($0) }
      consumers.append(stdErrConsumer)
      stdErr = .consumer(stdErrConsumer)
    }

    var environment = start.env
    var launchMode: ApplicationLaunchMode = start.foregroundIfRunning ? .foregroundIfRunning : .failIfRunning
    if start.enableRepl {
      // Setup the launch for the REPL (inject libRepl, the idb command API in libReplIDB, and the
      // IDB_REPL_* vars) and force a relaunch so an already-running, un-injected app picks them up.
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
    environment = await commandExecutor.audioInjectionAppLaunchEnvironment(environment)
    let config = ApplicationLaunchConfiguration(
      bundleID: start.bundleID,
      bundleName: nil,
      arguments: start.appArgs,
      environment: environment,
      waitForDebugger: start.waitForDebugger,
      stdOut: stdOut,
      stdErr: stdErr,
      launchMode: launchMode)
    let launchedApp = try await launch(config)
    let response = Idb_LaunchResponse.with {
      $0.debugger.pid = UInt64(launchedApp.processIdentifier)
    }
    try await responseStream.send(response)

    guard start.waitFor else { return }

    request = try await requestStream.requiredNext()
    guard case .stop = request.control else {
      throw RPCError(code: .failedPrecondition, message: "Application has already started")
    }

    try await launchedApp.terminate()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for consumer in consumers {
        group.addTask {
          try await consumer.awaitFinishedConsuming()
        }
      }
      try await group.waitForAll()
    }
  }

  /// Launches with the storage and target path placeholders in the environment replaced by their values.
  private func launch(_ configuration: ApplicationLaunchConfiguration) async throws -> LaunchedApplication {
    var replacements: [String: String] = [:]
    replacements.merge(commandExecutor.storageManager.replacementMapping) { _, new in new }
    replacements.merge(target.replacementMapping()) { _, new in new }
    let environment = applyEnvironmentReplacements(configuration.environment, replacements: replacements)

    let derived = ApplicationLaunchConfiguration(
      bundleID: configuration.bundleID,
      bundleName: configuration.bundleName,
      arguments: configuration.arguments,
      environment: environment,
      waitForDebugger: configuration.waitForDebugger,
      stdOut: configuration.stdOut,
      stdErr: configuration.stdErr,
      launchMode: configuration.launchMode
    )
    return try await target.application.launch(derived)
  }

  private func applyEnvironmentReplacements(_ environment: [String: String], replacements: [String: String]) -> [String: String] {
    let logger = commandExecutor.logger
    logger.log("Original environment: \(environment)")
    logger.log("Existing replacement mapping: \(replacements)")
    var interpolatedEnvironment: [String: String] = [:]
    for (name, var value) in environment {
      for (interpolationName, interpolationValue) in replacements {
        value = value.replacingOccurrences(of: interpolationName, with: interpolationValue)
      }
      interpolatedEnvironment[name] = value
    }
    logger.log("Interpolated environment: \(interpolatedEnvironment)")
    return interpolatedEnvironment
  }

  static func pipeOutput(interface: Idb_ProcessOutput.Interface, send: @escaping (Idb_LaunchResponse) throws -> Void) -> (DataConsumer & DataConsumerLifecycle) {
    return ResponseForwardingConsumer { data in
      let response = Idb_LaunchResponse.with {
        $0.output.data = data
        $0.output.interface = interface
      }
      try send(response)
    }
  }
}
