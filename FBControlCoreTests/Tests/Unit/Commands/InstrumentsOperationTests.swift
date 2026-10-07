/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class InstrumentsOperationTests: XCTestCase {

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

    let result = try await InstrumentsOperation.postProcess(
      arguments: nil, traceFile: traceFile, logger: nil)

    XCTAssertEqual(result, traceFile, "Absent post-processing arguments should pass the trace file straight through")
  }

  func testPostProcess_WhenArgumentsAreEmpty_ReturnsTheInputTraceFileWithoutSpawning() async throws {
    let traceFile = URL(fileURLWithPath: "/tmp/does-not-need-to-exist.trace")

    let result = try await InstrumentsOperation.postProcess(
      arguments: [], traceFile: traceFile, logger: nil)

    XCTAssertEqual(result, traceFile, "Empty post-processing arguments should pass the trace file straight through")
  }

  /// Runs `script` as the post-processing tool: `bash <script> <trace> -o <output> <extra...>`.
  private func postProcess(
    script: String, extraArguments: [String] = [], logger: (any ControlCoreLogger)? = nil
  ) async throws -> (traceFile: URL, result: URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let scriptFile = directory.appendingPathComponent("tool.sh")
    try script.write(to: scriptFile, atomically: true, encoding: .utf8)
    let traceFile = directory.appendingPathComponent("recording.trace")

    let result = try await InstrumentsOperation.postProcess(
      arguments: ["/bin/bash", scriptFile.path, "processed.trace"] + extraArguments,
      traceFile: traceFile, logger: logger)
    return (traceFile, result)
  }

  func testPostProcess_WhenToolSucceeds_ReturnsTheOutputBesideTheTrace() async throws {
    let (traceFile, result) = try await postProcess(
      script: #"printf '%s\n' "$@" > "$3""#, extraArguments: ["--extra", "value"])

    XCTAssertEqual(result, traceFile.deletingLastPathComponent().appendingPathComponent("processed.trace"))
    XCTAssertEqual(
      try String(contentsOf: result, encoding: .utf8),
      [traceFile.path, "-o", result.path, "--extra", "value"].joined(separator: "\n") + "\n",
      "The tool should receive the trace, the output path and the extra arguments in that order")
  }

  func testPostProcess_WhenToolExitsNonZero_Fails() async throws {
    do {
      _ = try await postProcess(script: "exit 7", logger: ControlCoreLoggerDouble())
      XCTFail("A non-zero exit from the post-processing tool should fail")
    } catch {
      XCTAssertTrue(
        error.localizedDescription.contains("is not acceptable"),
        "The failure should be the tool's unacceptable exit, got: \(error.localizedDescription)")
    }
  }

  func testPostProcess_HandsTheToolAnOpenStandardInputThatIsNeverWritten() async throws {
    // A pipe rules out /dev/null and a closed descriptor; a `read` that waits out its timeout rather
    // than returning at once rules out end-of-file. bash 3.2 exits 1 for both, hence the clock.
    // perl fstats descriptor 0 itself; `[ -p /dev/stdin ]` goes through devfs and fails on CI hosts.
    let (_, result) = try await postProcess(
      script: #"perl -e 'exit 3 unless -p STDIN' || exit 3; start=$SECONDS; read -t 2 _ && exit 4; [ $((SECONDS - start)) -ge 1 ] || exit 5; : > "$3""#)

    XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
  }

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

  private func configuration(operationDuration: TimeInterval) -> InstrumentsConfiguration {
    InstrumentsConfiguration.configuration(
      withTemplateName: "Time Profiler",
      targetApplication: "",
      appEnvironment: [:],
      appArguments: [],
      toolArguments: [],
      timings: InstrumentsTimings.timings(
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
    let arguments = InstrumentsOperation.launchArguments(
      udid: "UDID", configuration: configuration(operationDuration: 60), traceFile: "/tmp/trace.trace")

    XCTAssertEqual(try durationArgument(in: arguments), "60000")
  }

  /// `operationDuration` reaches this unclamped from the gRPC client, so a non-finite or enormous
  /// value has to format rather than trap - `Int(_: Double)` would abort the companion outright.
  func testLaunchArguments_DoNotTrapOnADurationThatCannotBeAnInteger() throws {
    for duration in [Double.infinity, -Double.infinity, Double.nan, Double.greatestFiniteMagnitude, 1e16] {
      let arguments = InstrumentsOperation.launchArguments(
        udid: "UDID", configuration: configuration(operationDuration: duration), traceFile: "/tmp/trace.trace")

      XCTAssertFalse(
        try durationArgument(in: arguments).isEmpty,
        "a duration of \(duration) should still produce an argument")
    }
  }

  func testLaunchArguments_PreserveSubMillisecondDurations() throws {
    let arguments = InstrumentsOperation.launchArguments(
      udid: "UDID", configuration: configuration(operationDuration: 0.0005), traceFile: "/tmp/trace.trace")

    XCTAssertEqual(try durationArgument(in: arguments), "0.5", "truncating to an integer would lose this")
  }
}

extension InstrumentsConsumer {

  fileprivate func consume(line: String) {
    consumeData(Data((line + "\n").utf8))
  }
}
