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

struct XctraceRecordMethodHandler {

  let logger: FBControlCoreLogger
  let targetLogger: FBControlCoreLogger
  let target: FBiOSTarget

  func handle(requestStream: GRPCAsyncRequestStream<Idb_XctraceRecordRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_XctraceRecordResponse>, context: GRPCAsyncServerCallContext) async throws {

    @Atomic var finishedWriting = false
    defer { _finishedWriting.set(true) }

    guard case let .start(start) = try await requestStream.requiredNext.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "Expected start control") }
    let operation = try await startXCTraceOperation(request: start, responseStream: responseStream, finishedWriting: _finishedWriting)

    guard case let .stop(stop) = try await requestStream.requiredNext.control
    else { throw GRPCStatus(code: .failedPrecondition, message: "Expected end control") }

    try await stopXCTrace(operation: operation, request: stop, responseStream: responseStream, finishedWriting: _finishedWriting)
  }

  private func startXCTraceOperation(request start: Idb_XctraceRecordRequest.Start, responseStream: GRPCAsyncResponseStreamWriter<Idb_XctraceRecordResponse>, finishedWriting: Atomic<Bool>) async throws -> FBXCTraceRecordOperation {
    let config = xcTraceRecordConfiguration(from: start)

    let responseWriter = FIFOStreamWriter(stream: responseStream)
    let consumer = FBBlockDataConsumer.asynchronousDataConsumer { data in
      guard !finishedWriting.wrappedValue else { return }

      let response = Idb_XctraceRecordResponse.with {
        $0.log = data
      }
      do {
        try responseWriter.send(response)
      } catch {
        finishedWriting.set(true)
      }
    }

    let logger = FBControlCoreLoggerFactory.compositeLogger(with: [
      FBControlCoreLoggerFactory.logger(to: consumer),
      targetLogger,
    ].compactMap({ $0 }))

    let operation = try await BridgeFuture.value(target.startXctraceRecord(config, logger: logger))
    let response = Idb_XctraceRecordResponse.with {
      $0.state = .running
    }
    try await responseStream.send(response)

    return operation
  }

  private func stopXCTrace(operation: FBXCTraceRecordOperation, request stop: Idb_XctraceRecordRequest.Stop, responseStream: GRPCAsyncResponseStreamWriter<Idb_XctraceRecordResponse>, finishedWriting: Atomic<Bool>) async throws {
    let stopTimeout = stop.timeout != 0 ? stop.timeout : DefaultXCTraceRecordStopTimeout
    _ = try await BridgeFuture.value(operation.stop(withTimeout: stopTimeout))
    let response = Idb_XctraceRecordResponse.with {
      $0.state = .processing
    }
    try await responseStream.send(response)

    let processed = try await BridgeFuture.value(
      FBInstrumentsOperation.postProcess(stop.args,
                                         traceDir: operation.traceDir,
                                         queue: BridgeQueues.miscEventReaderQueue,
                                         logger: logger)
    )
    finishedWriting.set(true)

    guard let path = processed.path else {
      throw GRPCStatus(code: .internalError, message: "Unable to get post process file path")
    }

    let data = try await BridgeFuture.value(FBArchiveOperations.createGzippedTarData(forPath: path, queue: BridgeQueues.futureSerialFullfillmentQueue, logger: targetLogger))
    let resp = Idb_XctraceRecordResponse.with {
      $0.payload = .with { $0.data = data as Data }
    }
    try await responseStream.send(resp)

    let createTarOperation = FBArchiveOperations.createGzippedTar(forPath: path, logger: logger)
    try await FileDrainWriter.performDrain(taskFuture: createTarOperation) { data in
      let response = Idb_XctraceRecordResponse.with {
        $0.payload = .with { $0.data = data }
      }
      try await responseStream.send(response)
    }
  }

  private func xcTraceRecordConfiguration(from request: Idb_XctraceRecordRequest.Start) -> FBXCTraceRecordConfiguration {
    let timeLimit = request.timeLimit != 0 ? request.timeLimit : DefaultXCTraceRecordOperationTimeLimit

    return .init(templateName: request.templateName,
                 timeLimit: timeLimit,
                 package: request.package,
                 allProcesses: request.target.allProcesses,
                 processToAttach: request.target.processToAttach,
                 processToLaunch: request.target.launchProcess.processToLaunch,
                 launchArgs: request.target.launchProcess.launchArgs,
                 targetStdin: request.target.launchProcess.targetStdin,
                 targetStdout: request.target.launchProcess.targetStdout,
                 processEnv: request.target.launchProcess.processEnv,
                 shim: nil)
  }
}
