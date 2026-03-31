/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCoreTestDoubles
import XCTest

@testable import FBControlCore

// swiftlint:disable force_cast
final class FBSubprocessTests: XCTestCase {

  private func startSynchronously<S: AnyObject, O: AnyObject, E: AnyObject>(_ builder: FBProcessBuilder<S, O, E>) -> FBSubprocess<S, O, E> {
    let future = builder.start()
    return try! future.`await`() as! FBSubprocess<S, O, E>
  }

  private func runAndWaitForTaskFuture<S: AnyObject, O: AnyObject, E: AnyObject>(_ future: FBFuture<FBSubprocess<S, O, E>>) -> FBSubprocess<S, O, E> {
    let erasedFuture = unsafeBitCast(future, to: FBFuture<AnyObject>.self)
    let timedFuture = FBFutureTestHelpers.applyTimeout(FBControlCoreGlobalConfiguration.regularTimeout, description: "FBTask to complete", to: erasedFuture)
    let _ = try? timedFuture.`await`()
    return future.result!
  }

  func testTrueExit() {
    let futureProcess = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/bin/sh", arguments: ["-c", "true"])
      .withTaskLifecycleLogging(to: FBControlCoreGlobalConfiguration.defaultLogger)
      .runUntilCompletion(withAcceptableExitCodes: nil)

    let process = runAndWaitForTaskFuture(futureProcess)
    XCTAssertEqual(process.exitCode.result, 0)
  }

  func testFalseExit() {
    let futureProcess = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/bin/sh", arguments: ["-c", "false"])
      .runUntilCompletion(withAcceptableExitCodes: [1])

    let process = runAndWaitForTaskFuture(futureProcess)
    XCTAssertEqual(process.exitCode.result, 1)
  }

  func testFalseExitWithStatusCodeError() throws {
    let future = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/bin/sh", arguments: ["-c", "false"])
      .runUntilCompletion(withAcceptableExitCodes: [0])

    XCTAssertThrowsError(try future.`await`())
  }

  func testEnvironment() {
    let environment: [String: String] = [
      "FOO0": "BAR0",
      "FOO1": "BAR1",
      "FOO2": "BAR2",
      "FOO3": "BAR3",
      "FOO4": "BAR4",
    ]
    let futureProcess = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/usr/bin/env")
      .withEnvironment(environment)
      .runUntilCompletion(withAcceptableExitCodes: nil)

    let process = runAndWaitForTaskFuture(futureProcess)
    XCTAssertEqual(process.exitCode.result, 0)
    let stdOut = process.stdOut as! String
    for key in environment.keys {
      let expected = "\(key)=\(environment[key]!)"
      XCTAssertTrue(stdOut.contains(expected))
    }
  }

  func testBase64Matches() {
    let filePath = TestFixtures.assetsdCrashPathWithCustomDeviceSet
    let expected = (try! Data(contentsOf: URL(fileURLWithPath: filePath))).base64EncodedString(options: [])

    let futureProcess = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/usr/bin/base64", arguments: ["-i", filePath])
      .runUntilCompletion(withAcceptableExitCodes: nil)
    let process = runAndWaitForTaskFuture(futureProcess)

    XCTAssertEqual(process.statLoc.state, FBFutureState.done)
    XCTAssertEqual(process.exitCode.state, FBFutureState.done)
    XCTAssertEqual(process.signal.state, FBFutureState.failed)
    XCTAssertEqual(process.stdOut as! String, expected)
    XCTAssertGreaterThan(process.processIdentifier, 1)
  }

  func testStringsOfCurrentBinary() {
    let bundlePath = Bundle(for: type(of: self)).bundlePath
    let binaryName = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
    let binaryPath = ((bundlePath as NSString).appendingPathComponent("Contents/MacOS") as NSString).appendingPathComponent(binaryName)

    let futureProcess = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/usr/bin/strings", arguments: [binaryPath])
      .runUntilCompletion(withAcceptableExitCodes: nil)
    let process = runAndWaitForTaskFuture(futureProcess)

    XCTAssertEqual(process.statLoc.state, FBFutureState.done)
    XCTAssertEqual(process.exitCode.state, FBFutureState.done)
    XCTAssertEqual(process.signal.state, FBFutureState.failed)
    XCTAssertTrue((process.stdOut as! String).contains("testStringsOfCurrentBinary"))
    XCTAssertGreaterThan(process.processIdentifier, 1)
  }

  func testBundleContents() {
    let bundle = Bundle(for: type(of: self))
    let resourcesPath = (bundle.bundlePath as NSString).appendingPathComponent("Contents/Resources")

    let futureProcess = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/bin/ls", arguments: ["-1", resourcesPath])
      .runUntilCompletion(withAcceptableExitCodes: nil)
    let process = runAndWaitForTaskFuture(futureProcess)

    XCTAssertEqual(process.statLoc.state, FBFutureState.done)
    XCTAssertEqual(process.exitCode.state, FBFutureState.done)
    XCTAssertEqual(process.signal.state, FBFutureState.failed)
    XCTAssertGreaterThan(process.processIdentifier, 1)

    let fileNames = (process.stdOut as! String).components(separatedBy: .newlines)
    XCTAssertGreaterThanOrEqual(fileNames.count, 2)

    for fileName in fileNames {
      let path = bundle.path(forResource: fileName, ofType: nil)
      XCTAssertNotNil(path)
    }
  }

  func testLineReader() {
    let filePath = TestFixtures.assetsdCrashPathWithCustomDeviceSet
    let lines = NSMutableArray()

    let futureProcess = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/usr/bin/grep", arguments: ["CoreFoundation", filePath])
      .withStdOutLineReader { line in
        lines.add(line)
      }
      .runUntilCompletion(withAcceptableExitCodes: nil)
    let process = runAndWaitForTaskFuture(futureProcess)

    XCTAssertEqual(process.statLoc.state, FBFutureState.done)
    XCTAssertEqual(process.exitCode.state, FBFutureState.done)
    XCTAssertEqual(process.signal.state, FBFutureState.failed)
    XCTAssertTrue((process.stdOut as AnyObject).conforms(to: FBDataConsumer.self))
    XCTAssertGreaterThan(process.processIdentifier, 1)

    let _ = try? FBFuture<AnyObject>.empty().delay(2).`await`()
    XCTAssertEqual(lines.count, 8)
    XCTAssertEqual(lines[0] as! String, "0   CoreFoundation                      0x0138ba14 __exceptionPreprocess + 180")
  }

  func testLogger() {
    let bundlePath = Bundle(for: type(of: self)).bundlePath

    let futureProcess = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/usr/bin/file", arguments: [bundlePath])
      .withStdErr(to: FBControlCoreLoggerDouble())
      .withStdOut(to: FBControlCoreLoggerDouble())
      .runUntilCompletion(withAcceptableExitCodes: nil)
    let process = runAndWaitForTaskFuture(futureProcess)

    XCTAssertEqual(process.statLoc.state, FBFutureState.done)
    XCTAssertEqual(process.exitCode.state, FBFutureState.done)
    XCTAssertEqual(process.signal.state, FBFutureState.failed)
    XCTAssertTrue((process.stdOut as AnyObject).isKind(of: FBControlCoreLoggerDouble.self))
    XCTAssertTrue((process.stdErr as AnyObject).isKind(of: FBControlCoreLoggerDouble.self))
  }

  func testDevNull() {
    let bundlePath = Bundle(for: type(of: self)).bundlePath

    let futureProcess = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/usr/bin/file", arguments: [bundlePath])
      .withStdOutToDevNull()
      .withStdErrToDevNull()
      .runUntilCompletion(withAcceptableExitCodes: nil)
    let process = runAndWaitForTaskFuture(futureProcess)

    XCTAssertEqual(process.statLoc.state, FBFutureState.done)
    XCTAssertEqual(process.exitCode.state, FBFutureState.done)
    XCTAssertEqual(process.signal.state, FBFutureState.failed)
    XCTAssertNil(process.stdOut)
    XCTAssertNil(process.stdErr)
  }

  func testUpdatesStateWithAsynchronousTermination() throws {
    let process = startSynchronously(
      FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/bin/sleep", arguments: ["1"])
    )

    try process.exitCode.await(withTimeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testAwaitingTerminationOfShortLivedProcess() throws {
    let process = startSynchronously(
      FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/bin/sleep", arguments: ["0"])
    )

    XCTAssertNotNil(try process.exitCode.await(withTimeout: 1))
    XCTAssertEqual(process.statLoc.state, FBFutureState.done)
    XCTAssertEqual(process.exitCode.state, FBFutureState.done)
    XCTAssertEqual(process.signal.state, FBFutureState.failed)
  }

  func testCallsHandlerWithAsynchronousTermination() {
    let expectation = XCTestExpectation(description: "Termination Handler Called")
    FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/bin/sleep", arguments: ["1"])
      .runUntilCompletion(withAcceptableExitCodes: nil)
      .onQueue(
        DispatchQueue.main,
        notifyOfCompletion: { _ in
          expectation.fulfill()
        })

    wait(for: [expectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testAwaitingTerminationDoesNotTerminateStalledTask() throws {
    let expectation = XCTestExpectation(description: "Termination Handler Called")
    expectation.isInverted = true
    let process = startSynchronously(
      FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/bin/sleep", arguments: ["1000"])
    )

    process.statLoc.onQueue(
      DispatchQueue.main,
      notifyOfCompletion: { _ in
        expectation.fulfill()
      })

    XCTAssertThrowsError(try process.exitCode.await(withTimeout: 2))
    XCTAssertFalse(process.statLoc.hasCompleted)
    XCTAssertFalse(process.exitCode.hasCompleted)
    XCTAssertFalse(process.signal.hasCompleted)

    wait(for: [expectation], timeout: 2)
  }

  func testInputReading() throws {
    let expected = "FOO BAR BAZ".data(using: .utf8)!

    let process = startSynchronously(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/bin/cat", arguments: [])
        .withStdInConnected()
        .withStdOutInMemoryAsData()
        .withStdErrToDevNull()
    )

    XCTAssertTrue((process.stdIn as AnyObject).conforms(to: FBDataConsumer.self))
    (process.stdIn as! FBDataConsumer).consumeData(expected)
    (process.stdIn as! FBDataConsumer).consumeEndOfFile()

    let waitSuccess = try process.exitCode.await(withTimeout: 2) != nil
    XCTAssertTrue(waitSuccess)

    XCTAssertEqual(expected, process.stdOut as! Data)
  }

  func testInputStream() throws {
    let expected = "FOO BAR BAZ"

    let input = FBProcessInput<OutputStream>.fromStream()
    let stream: OutputStream = input.contents

    let process = startSynchronously(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/bin/cat", arguments: [])
        .withStdIn(unsafeBitCast(input, to: FBProcessInput<AnyObject>.self))
        .withStdOutInMemoryAsString()
        .withStdErrToDevNull()
    )

    XCTAssertTrue(stream is OutputStream)
    XCTAssertTrue(process.stdIn is OutputStream)
    stream.open()
    let bytes = Array(expected.utf8)
    stream.write(bytes, maxLength: bytes.count)
    stream.close()

    let waitSuccess = try process.exitCode.await(withTimeout: 2) != nil
    XCTAssertTrue(waitSuccess)

    XCTAssertEqual(expected, process.stdOut as! String)
  }

  func testInputStreamWithBrokenPipe() throws {
    let expected = "FOO BAR BAZ"

    let input = FBProcessInput<OutputStream>.fromStream()
    let stream: OutputStream = input.contents

    let process = startSynchronously(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/bin/cat", arguments: [])
        .withStdIn(unsafeBitCast(input, to: FBProcessInput<AnyObject>.self))
        .withStdOutInMemoryAsString()
        .withStdErrToDevNull()
    )

    XCTAssertTrue(stream is OutputStream)
    XCTAssertTrue(process.stdIn is OutputStream)
    stream.open()
    let bytes = Array(expected.utf8)
    stream.write(bytes, maxLength: bytes.count)
    stream.close()

    XCTAssertEqual(stream.write(bytes, maxLength: bytes.count), -1)
    XCTAssertNotNil(stream.streamError)

    let waitSuccess = try process.exitCode.await(withTimeout: 2) != nil
    XCTAssertTrue(waitSuccess)

    XCTAssertEqual(expected, process.stdOut as! String)
  }

  func testOutputStream() throws {
    let expected = "FOO BAR BAZ"

    let process = startSynchronously(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/bin/echo", arguments: ["FOO BAR BAZ"])
        .withStdErrToDevNull()
        .withStdOutToInputStream()
    )

    let stream = process.stdOut as! InputStream
    XCTAssertTrue(stream is InputStream)
    stream.open()

    var output = Data()
    while true {
      var buffer = [UInt8](repeating: 0, count: 8)
      let result = stream.read(&buffer, maxLength: 8)
      if result < 1 {
        break
      }
      output.append(buffer, count: result)
    }
    let actual = String(data: output, encoding: .ascii)!.trimmingCharacters(in: .newlines)
    XCTAssertEqual(expected, actual)

    let waitSuccess = try process.exitCode.await(withTimeout: 2) != nil
    XCTAssertTrue(waitSuccess)
  }

  func testInputFromData() throws {
    let expected = "FOO BAR BAZ".data(using: .utf8)!

    let process = startSynchronously(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/bin/cat", arguments: [])
        .withStdIn(from: expected)
        .withStdOutInMemoryAsData()
        .withStdErrToDevNull()
    )

    let waitSuccess = try process.exitCode.await(withTimeout: 2) != nil
    XCTAssertTrue(waitSuccess)

    XCTAssertEqual(expected, process.stdOut as! Data)
  }

  func testSendingSIGINT() throws {
    let process = startSynchronously(
      FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/bin/sleep", arguments: ["1000000"])
    )

    XCTAssertEqual(process.statLoc.state, FBFutureState.running)
    XCTAssertEqual(process.exitCode.state, FBFutureState.running)
    XCTAssertEqual(process.signal.state, FBFutureState.running)

    try process.sendSignal(SIGINT).`await`()
    XCTAssertEqual(process.exitCode.state, FBFutureState.failed)
    XCTAssertEqual(process.signal.state, FBFutureState.done)
    XCTAssertEqual(process.signal.result, NSNumber(value: SIGINT))
  }

  func testSendingSIGKILL() throws {
    let process = startSynchronously(
      FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/bin/sleep", arguments: ["1000000"])
    )

    XCTAssertEqual(process.statLoc.state, FBFutureState.running)
    XCTAssertEqual(process.exitCode.state, FBFutureState.running)
    XCTAssertEqual(process.signal.state, FBFutureState.running)

    try process.sendSignal(SIGKILL).`await`()
    XCTAssertEqual(process.statLoc.state, FBFutureState.done)
    XCTAssertEqual(process.exitCode.state, FBFutureState.failed)
    XCTAssertEqual(process.signal.state, FBFutureState.done)
    XCTAssertEqual(process.signal.result, NSNumber(value: SIGKILL))
  }

  func testHUPBackoffToKILL() throws {
    let process = startSynchronously(
      FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/usr/bin/nohup", arguments: ["/bin/sleep", "10000000"])
    )

    XCTAssertEqual(process.statLoc.state, FBFutureState.running)
    XCTAssertEqual(process.exitCode.state, FBFutureState.running)
    XCTAssertEqual(process.signal.state, FBFutureState.running)

    try process.sendSignal(SIGHUP, backingOffToKillWithTimeout: 0.5, logger: FBControlCoreLoggerDouble()).`await`()
    XCTAssertEqual(process.statLoc.state, FBFutureState.done)
    XCTAssertEqual(process.exitCode.state, FBFutureState.failed)
    XCTAssertEqual(process.signal.state, FBFutureState.done)
    XCTAssertEqual(process.signal.result!.int32Value, SIGKILL)

    try process.statLoc.`await`()
    XCTAssertEqual(process.statLoc.state, FBFutureState.done)
    XCTAssertEqual(process.exitCode.state, FBFutureState.failed)
    XCTAssertEqual(process.signal.state, FBFutureState.done)
  }

  func testPipingInputToSuccessivelyRunTasksSucceeds() throws {
    let tarSource = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(UUID().uuidString).tar.gz")
    let tarDestination = tarSource + ".destination"

    try FileManager.default.createDirectory(atPath: tarDestination, withIntermediateDirectories: true, attributes: nil)

    try FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/usr/bin/tar")
      .withArguments(["-zcvf", tarSource, TestFixtures.bundleResource])
      .withStdOutToDevNull()
      .withStdErrToDevNull()
      .runUntilCompletion(withAcceptableExitCodes: nil)
      .mapReplace(NSNull())
      .`await`()

    let tarData = try Data(contentsOf: URL(fileURLWithPath: tarSource))

    for _ in 0..<10 {
      try FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/usr/bin/tar")
        .withArguments(["-C", tarDestination, "-zxpf", "-"])
        .withStdIn(from: tarData)
        .withStdOutToDevNull()
        .withStdErrToDevNull()
        .runUntilCompletion(withAcceptableExitCodes: nil)
        .mapReplace(NSNull())
        .`await`()
    }
  }
}
// swiftlint:enable force_cast
