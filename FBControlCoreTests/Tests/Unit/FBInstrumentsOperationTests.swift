/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBInstrumentsOperationTests: XCTestCase {

  // MARK: - Lifecycle Markers

  func testConsumer_WhenTemplateLoadingLineArrives_ResolvesTheTemplateLoadedMarker() async throws {
    let consumer = InstrumentsConsumer()

    consumer.consume(line: "Loading template 'Time Profiler'")

    let resolved = await waitForCompletion(of: consumer.hasStartedLoadingTemplate)
    XCTAssertTrue(resolved, "A 'Loading template' line should resolve the template-loaded marker")
    XCTAssertFalse(consumer.hasStoppedRecording.hasCompleted, "Loading a template is not a stop")
  }

  func testConsumer_WhenTraceCompleteLineArrives_FailsWithTheAccumulatedLogs() async throws {
    let consumer = InstrumentsConsumer()

    consumer.consume(line: "Recording something interesting")
    consumer.consume(line: "Instruments Trace Complete")

    let resolved = await waitForCompletion(of: consumer.hasStoppedRecording)
    XCTAssertTrue(resolved, "An 'Instruments Trace Complete' line should resolve the stopped-recording marker")

    let error = try XCTUnwrap(consumer.hasStoppedRecording.error, "Stopping prematurely should be a failure, not a success")
    XCTAssertTrue(
      error.localizedDescription.contains("Recording something interesting"),
      "The failure should carry the accumulated instruments logs, got: \(error.localizedDescription)")
  }

  func testConsumer_WhenUnrelatedLinesArrive_ResolvesNeitherMarker() async throws {
    let consumer = InstrumentsConsumer()

    consumer.consume(line: "Some incidental instruments chatter")

    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertFalse(consumer.hasStartedLoadingTemplate.hasCompleted, "An unrelated line should not signal template loading")
    XCTAssertFalse(consumer.hasStoppedRecording.hasCompleted, "An unrelated line should not signal a stop")
  }

  // MARK: - Post Processing

  func testPostProcess_WhenArgumentsAreNil_ReturnsTheInputTraceFileWithoutSpawning() async throws {
    let traceFile = URL(fileURLWithPath: "/tmp/does-not-need-to-exist.trace")

    let result = try await FBInstrumentsOperation.postProcessAsync(
      arguments: nil, traceFile: traceFile, queue: .main, logger: nil)

    XCTAssertEqual(result, traceFile, "Absent post-processing arguments should pass the trace file straight through")
  }

  func testPostProcess_WhenArgumentsAreEmpty_ReturnsTheInputTraceFileWithoutSpawning() async throws {
    let traceFile = URL(fileURLWithPath: "/tmp/does-not-need-to-exist.trace")

    let result = try await FBInstrumentsOperation.postProcessAsync(
      arguments: [], traceFile: traceFile, queue: .main, logger: nil)

    XCTAssertEqual(result, traceFile, "Empty post-processing arguments should pass the trace file straight through")
  }

  // MARK: - Helpers

  /// The consumer parses lines asynchronously on the block consumer's own queue, so the
  /// markers resolve some time after the data is fed in.
  private func waitForCompletion(of future: FBMutableFuture<NSNull>, timeout: TimeInterval = 5) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if future.hasCompleted {
        return true
      }
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return false
  }

  // MARK: - Launch Arguments

  private func configuration(operationDuration: TimeInterval) -> FBInstrumentsConfiguration {
    FBInstrumentsConfiguration.configuration(
      withTemplateName: "Time Profiler",
      targetApplication: "",
      appEnvironment: [:],
      appArguments: [],
      toolArguments: [],
      timings: FBInstrumentsTimings.timings(
        withTerminateTimeout: DefaultInstrumentsTerminateTimeout,
        launchRetryTimeout: DefaultInstrumentsLaunchRetryTimeout,
        launchErrorTimeout: DefaultInstrumentsLaunchErrorTimeout,
        operationDuration: operationDuration))
  }

  private func durationArgument(in arguments: [String]) throws -> String {
    let index = try XCTUnwrap(arguments.firstIndex(of: "-l"), "the command line should carry a duration")
    return arguments[index + 1]
  }

  func testLaunchArguments_CarryTheDurationInMilliseconds() throws {
    let arguments = FBInstrumentsOperation.launchArguments(
      udid: "UDID", configuration: configuration(operationDuration: 60), traceFile: "/tmp/trace.trace")

    XCTAssertEqual(try durationArgument(in: arguments), "60000")
  }

  /// `operationDuration` reaches this unclamped from the gRPC client, so a non-finite or enormous
  /// value has to format rather than trap - `Int(_: Double)` would abort the companion outright.
  func testLaunchArguments_DoNotTrapOnADurationThatCannotBeAnInteger() throws {
    for duration in [Double.infinity, -Double.infinity, Double.nan, Double.greatestFiniteMagnitude, 1e16] {
      let arguments = FBInstrumentsOperation.launchArguments(
        udid: "UDID", configuration: configuration(operationDuration: duration), traceFile: "/tmp/trace.trace")

      XCTAssertFalse(
        try durationArgument(in: arguments).isEmpty,
        "a duration of \(duration) should still produce an argument")
    }
  }

  func testLaunchArguments_PreserveSubMillisecondDurations() throws {
    let arguments = FBInstrumentsOperation.launchArguments(
      udid: "UDID", configuration: configuration(operationDuration: 0.0005), traceFile: "/tmp/trace.trace")

    XCTAssertEqual(try durationArgument(in: arguments), "0.5", "truncating to an integer would lose this")
  }
}

extension InstrumentsConsumer {

  fileprivate func consume(line: String) {
    consumeData(Data((line + "\n").utf8))
  }
}
