/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBSimulatorControl
import GRPC
import IDBCompanionUtilities
import IDBGRPCSwift

struct InstrumentsRunMethodHandler {

  let target: FBiOSTarget
  let targetLogger: FBControlCoreLogger
  let commandExecutor: FBIDBCommandExecutor
  let logger: FBControlCoreLogger

  func handle(requestStream: GRPCAsyncRequestStream<Idb_InstrumentsRunRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstrumentsRunResponse>, context: GRPCAsyncServerCallContext) async throws {
    @Atomic var finishedWriting = false

    guard case let .start(start) = try await requestStream.requiredNext.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "Expected start control") }

    let operation = try await startInstrumentsOperation(request: start, responseStream: responseStream, finishedWriting: _finishedWriting)

    guard case let .stop(stop) = try await requestStream.requiredNext.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "Expected end control") }

    try await stopInstruments(operation: operation, request: stop, responseStream: responseStream, finishedWriting: _finishedWriting)
  }

  private func startInstrumentsOperation(request: Idb_InstrumentsRunRequest.Start, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstrumentsRunResponse>, finishedWriting: Atomic<Bool>) async throws -> FBInstrumentsOperation {
    let configuration = instrumentsConfiguration(from: request, storageManager: commandExecutor.storageManager)

    let responseWriter = FIFOStreamWriter(stream: responseStream)
    let consumer = FBBlockDataConsumer.asynchronousDataConsumer { data in
      guard !finishedWriting.wrappedValue else { return }

      do {
        let response = Idb_InstrumentsRunResponse.with {
          $0.logOutput = data
        }
        try responseWriter.send(response)
      } catch {
        finishedWriting.set(true)
      }
    }
    let logger = FBControlCoreLoggerFactory.compositeLogger(with: [
      FBControlCoreLoggerFactory.logger(to: consumer),
      targetLogger,
    ].compactMap { $0 })

    let operation = try await BridgeFuture.value(target.startInstruments(configuration, logger: logger))

    let runningStateResponse = Idb_InstrumentsRunResponse.with {
      $0.output = .state(.runningInstruments)
    }
    try await responseStream.send(runningStateResponse)

    return operation
  }

  private func stopInstruments(operation: FBInstrumentsOperation, request: Idb_InstrumentsRunRequest.Stop, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstrumentsRunResponse>, finishedWriting: Atomic<Bool>) async throws {
    _ = try await BridgeFuture.value(operation.stop())
    let response = Idb_InstrumentsRunResponse.with {
      $0.state = .postProcessing
    }
    try await responseStream.send(response)

    let postProcessArguments = commandExecutor.storageManager.interpolateArgumentReplacements(request.postProcessArguments)
    let processed = try await BridgeFuture.value(FBInstrumentsOperation.postProcess(postProcessArguments,
                                                                                    traceDir: operation.traceDir,
                                                                                    queue: BridgeQueues.futureSerialFullfillmentQueue,
                                                                                    logger: logger))
    guard let processedPath = processed.path else {
      throw GRPCStatus(code: .internalError, message: "Unable to get post process file path")
    }
    finishedWriting.set(true)

    let archiveOperation = FBArchiveOperations.createGzippedTar(forPath: processedPath, logger: logger)

    try await FileDrainWriter.performDrain(taskFuture: archiveOperation) { data in
      let response = Idb_InstrumentsRunResponse.with {
        $0.payload = .with {
          $0.data = data
        }
      }
      try await responseStream.send(response)
    }
  }

  private func instrumentsConfiguration(from request: Idb_InstrumentsRunRequest.Start, storageManager: FBIDBStorageManager) -> FBInstrumentsConfiguration {
    func withDefaultTimeout(_ initial: Double, _ default: Double) -> Double {
      initial != 0 ? initial : `default`
    }
    return .init(templateName: request.templateName,
                 targetApplication: request.appBundleID,
                 appEnvironment: request.environment,
                 appArguments: request.arguments,
                 toolArguments: storageManager.interpolateArgumentReplacements(request.toolArguments) ?? [],
                 timings: .init(terminateTimeout: withDefaultTimeout(request.timings.terminateTimeout, DefaultInstrumentsTerminateTimeout),
                                launchRetryTimeout: withDefaultTimeout(request.timings.launchRetryTimeout, DefaultInstrumentsLaunchRetryTimeout),
                                launchErrorTimeout: withDefaultTimeout(request.timings.launchErrorTimeout, DefaultInstrumentsLaunchErrorTimeout),
                                operationDuration: withDefaultTimeout(request.timings.operationDuration, DefaultInstrumentsOperationDuration)))
  }
}
