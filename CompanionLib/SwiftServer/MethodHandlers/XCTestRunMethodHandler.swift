/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
import FBControlCore
import FBSimulatorControl
import FBXCTestCore
import Foundation
import GRPCCore
import IDBGRPCSwift

/// Seam over a started test run, so the handler can be tested against a double.
protocol XCTestRunCompletion {
  func awaitCompletion() async throws
}

extension IDBTestOperation: XCTestRunCompletion {}

struct XCTestRunMethodHandler {

  let target: any Target
  let commandExecutor: IDBCommandExecutor
  let reporter: EventReporter
  let targetLogger: ControlCoreLogger
  let logger: IDBLogger

  func handle(request: Idb_XctestRunRequest, responseStream: RPCWriter<Idb_XctestRunResponse>, context: ServerContext) async throws {
    guard let transformed = transform(value: request) else {
      throw RPCError(code: .invalidArgument, message: "failed to create XCTestRunRequest")
    }

    let reporter = IDBXCTestReporter(responseStream: responseStream, logger: logger)
    // The request is not mutated once built, but is not Sendable; rebind as nonisolated(unsafe) so the
    // run can capture it.
    nonisolated(unsafe) let request = transformed

    try await Self.run(
      cancellation: context.cancellation,
      start: { [commandExecutor] in
        let operation = try await commandExecutor.xctest_run(
          request,
          reporter: reporter,
          logger: FBControlCoreLoggerFactory.logger(to: reporter))
        reporter.configuration = .init(legacy: operation.reporterConfiguration)
        return operation
      },
      reportingTerminated: { _ = try await reporter.awaitReportingTerminated() })
  }

  /// Awaits the run `start` begins, then its reporting, unless `cancellation` reports the RPC cancelled, as
  /// it does when the client goes away, which cancels the run.
  static func run(
    cancellation: ServerContext.RPCCancellationHandle,
    start: @escaping @Sendable () async throws -> any XCTestRunCompletion,
    reportingTerminated: @escaping @Sendable () async throws -> Void
  ) async throws {
    try await withRPCCancellation(cancellation) {
      let operation = try await start()
      do {
        try await operation.awaitCompletion()
      } catch let error as NSError {
        // We should ignore errors that came from test binary. Like when an exception is thrown or binary crashed.
        if error.domain != FBTestErrorDomain {
          throw error
        }
      }

      try await reportingTerminated()
    }
  }

  func transform(value request: Idb_XctestRunRequest) -> XCTestRunRequest? {
    let testsToRun = request.testsToRun.isEmpty ? nil : Set(request.testsToRun)
    switch request.mode.mode {
    case .logic:
      return XCTestRunRequest.logicTest(
        withTestBundleID: request.testBundleID,
        environment: request.environment,
        arguments: request.arguments,
        testsToRun: testsToRun,
        testsToSkip: Set(request.testsToSkip),
        testTimeout: TimeInterval(request.timeout),
        reportActivities: request.reportActivities,
        reportAttachments: request.reportAttachments,
        coverageRequest: extractCodeCoverage(from: request),
        collectLogs: request.collectLogs,
        waitForDebugger: request.waitForDebugger,
        collectResultBundle: request.collectResultBundle)
    case let .application(app):
      return XCTestRunRequest.applicationTest(
        withTestBundleID: request.testBundleID,
        testHostAppBundleID: app.appBundleID,
        environment: request.environment,
        arguments: request.arguments,
        testsToRun: testsToRun,
        testsToSkip: Set(request.testsToSkip),
        testTimeout: TimeInterval(request.timeout),
        reportActivities: request.reportActivities,
        reportAttachments: request.reportAttachments,
        coverageRequest: extractCodeCoverage(from: request),
        collectLogs: request.collectLogs,
        waitForDebugger: request.waitForDebugger,
        collectResultBundle: request.collectResultBundle)
    case let .ui(ui):
      return XCTestRunRequest.uiTest(
        withTestBundleID: request.testBundleID,
        testHostAppBundleID: ui.testHostAppBundleID,
        testTargetAppBundleID: ui.appBundleID,
        environment: request.environment,
        arguments: request.arguments,
        testsToRun: testsToRun,
        testsToSkip: Set(request.testsToSkip),
        testTimeout: TimeInterval(request.timeout),
        reportActivities: request.reportActivities,
        reportAttachments: request.reportAttachments,
        coverageRequest: extractCodeCoverage(from: request),
        collectLogs: request.collectLogs,
        collectResultBundle: request.collectResultBundle)
    case .none:
      return nil
    }
  }

  private func extractCodeCoverage(from request: Idb_XctestRunRequest) -> CodeCoverageRequest {
    if request.hasCodeCoverage {
      switch request.codeCoverage.format {
      case .raw:
        return CodeCoverageRequest(collect: request.codeCoverage.collect, format: .raw, enableContinuousCoverageCollection: request.codeCoverage.enableContinuousCoverageCollection)
      case .exported, .UNRECOGNIZED:
        return CodeCoverageRequest(collect: request.codeCoverage.collect, format: .exported, enableContinuousCoverageCollection: request.codeCoverage.enableContinuousCoverageCollection)
      }
    }
    // fallback to deprecated request field for backwards compatibility
    return CodeCoverageRequest(collect: request.collectCoverage, format: .exported, enableContinuousCoverageCollection: request.codeCoverage.enableContinuousCoverageCollection)
  }
}
