/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
import XCTestBootstrap

// MARK: - FBCodeCoverageConfiguration Tests

final class FBCodeCoverageConfigurationTransientTests: XCTestCase {

  func testInitWithExportedFormat() {
    let config = FBCodeCoverageConfiguration(
      directory: "/tmp/coverage",
      format: .exported,
      enableContinuousCoverageCollection: false
    )
    XCTAssertEqual(config.coverageDirectory, "/tmp/coverage")
    XCTAssertEqual(config.format, .exported)
    XCTAssertFalse(config.shouldEnableContinuousCoverageCollection)
  }

  func testInitWithRawFormat() {
    let config = FBCodeCoverageConfiguration(
      directory: "/var/coverage",
      format: .raw,
      enableContinuousCoverageCollection: true
    )
    XCTAssertEqual(config.coverageDirectory, "/var/coverage")
    XCTAssertEqual(config.format, .raw)
    XCTAssertTrue(config.shouldEnableContinuousCoverageCollection)
  }

  func testDescriptionContainsDirectory() {
    let config = FBCodeCoverageConfiguration(
      directory: "/my/dir",
      format: .exported,
      enableContinuousCoverageCollection: false
    )
    let desc = config.description
    XCTAssertTrue(desc.contains("/my/dir"), "Description should contain the coverage directory")
  }
}

// MARK: - FBExceptionInfo Tests

final class FBExceptionInfoTransientTests: XCTestCase {

  func testInitWithMessageFileAndLine() {
    let exception = FBExceptionInfo(message: "Something failed", file: "/path/to/File.m", line: 42)
    XCTAssertEqual(exception.message, "Something failed")
    XCTAssertEqual(exception.file, "/path/to/File.m")
    XCTAssertEqual(exception.line, 42)
  }

  func testInitWithMessageOnly() {
    let exception = FBExceptionInfo(message: "Crash occurred")
    XCTAssertEqual(exception.message, "Crash occurred")
    XCTAssertNil(exception.file)
    XCTAssertEqual(exception.line, 0)
  }

  func testDescriptionContainsMessage() {
    let exception = FBExceptionInfo(message: "test failure", file: "Test.m", line: 10)
    let desc = exception.description
    XCTAssertTrue(desc.contains("test failure"), "Description should contain the message")
    XCTAssertTrue(desc.contains("Test.m"), "Description should contain the file")
  }
}

// MARK: - FBTestManagerResultSummary Tests

final class FBTestManagerResultSummaryTransientTests: XCTestCase {

  func testDirectInit() {
    let date = Date(timeIntervalSince1970: 1000)
    let summary = FBTestManagerResultSummary(
      testSuite: "MySuite",
      finishTime: date,
      runCount: 10,
      failureCount: 2,
      unexpected: 1,
      testDuration: 5.5,
      totalDuration: 6.0
    )
    XCTAssertEqual(summary.testSuite, "MySuite")
    XCTAssertEqual(summary.finishTime, date)
    XCTAssertEqual(summary.runCount, 10)
    XCTAssertEqual(summary.failureCount, 2)
    XCTAssertEqual(summary.unexpected, 1)
    XCTAssertEqual(summary.testDuration, 5.5, accuracy: 0.001)
    XCTAssertEqual(summary.totalDuration, 6.0, accuracy: 0.001)
  }

  func testInitWithZeroCounts() {
    let date = Date()
    let summary = FBTestManagerResultSummary(
      testSuite: "EmptySuite",
      finishTime: date,
      runCount: 0,
      failureCount: 0,
      unexpected: 0,
      testDuration: 0.0,
      totalDuration: 0.0
    )
    XCTAssertEqual(summary.testSuite, "EmptySuite")
    XCTAssertEqual(summary.runCount, 0)
    XCTAssertEqual(summary.failureCount, 0)
    XCTAssertEqual(summary.unexpected, 0)
    XCTAssertEqual(summary.testDuration, 0.0, accuracy: 0.001)
    XCTAssertEqual(summary.totalDuration, 0.0, accuracy: 0.001)
  }

  func testStatusForStatusString() {
    XCTAssertEqual(FBTestManagerResultSummary.status(forStatusString: "passed"), .passed)
    XCTAssertEqual(FBTestManagerResultSummary.status(forStatusString: "failed"), .failed)
    XCTAssertEqual(FBTestManagerResultSummary.status(forStatusString: "unknown"), .unknown)
    XCTAssertEqual(FBTestManagerResultSummary.status(forStatusString: "something-else"), .unknown)
    XCTAssertEqual(FBTestManagerResultSummary.status(forStatusString: ""), .unknown)
  }

  func testStatusStringForStatus() {
    XCTAssertEqual(FBTestManagerResultSummary.statusString(for: .passed), "Passed")
    XCTAssertEqual(FBTestManagerResultSummary.statusString(for: .failed), "Failed")
    XCTAssertEqual(FBTestManagerResultSummary.statusString(for: .unknown), "Unknown")
  }

  func testEquality() {
    let date = Date(timeIntervalSince1970: 500)
    let summary1 = FBTestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    let summary2 = FBTestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    XCTAssertEqual(summary1, summary2)
  }

  func testInequality() {
    let date = Date(timeIntervalSince1970: 500)
    let summary1 = FBTestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    let summary2 = FBTestManagerResultSummary(
      testSuite: "DifferentSuite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    XCTAssertNotEqual(summary1, summary2)
  }

  func testInequalityByRunCount() {
    let date = Date(timeIntervalSince1970: 500)
    let summary1 = FBTestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    let summary2 = FBTestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 99, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    XCTAssertNotEqual(summary1, summary2)
  }

  func testDescriptionContainsSuiteName() {
    let summary = FBTestManagerResultSummary(
      testSuite: "DescSuite", finishTime: Date(), runCount: 1, failureCount: 0,
      unexpected: 0, testDuration: 1.0, totalDuration: 1.0
    )
    XCTAssertTrue(summary.description.contains("DescSuite"))
  }
}

// MARK: - FBXCTestConfiguration Subclass Tests

final class FBXCTestConfigurationTransientTests: XCTestCase {

  // MARK: FBListTestConfiguration

  private func makeListConfig(
    env: [String: String] = [:],
    workDir: String = "/tmp",
    bundlePath: String = "/bundle.xctest",
    runnerAppPath: String? = nil,
    waitForDebugger: Bool = false,
    timeout: TimeInterval = 100,
    architectures: Set<String> = ["x86_64"]
  ) -> FBListTestConfiguration {
    return FBListTestConfiguration(
      environment: env,
      workingDirectory: workDir,
      testBundlePath: bundlePath,
      runnerAppPath: runnerAppPath,
      waitForDebugger: waitForDebugger,
      timeout: timeout,
      architectures: architectures
    )
  }

  private func makeLogicConfig(
    env: [String: String] = [:],
    workDir: String = "/tmp",
    bundlePath: String = "/logic.xctest",
    waitForDebugger: Bool = false,
    timeout: TimeInterval = 100,
    testFilter: String? = nil,
    mirroring: FBLogicTestMirrorLogs = [],
    coverageConfiguration: FBCodeCoverageConfiguration? = nil,
    binaryPath: String? = nil,
    logDirectoryPath: String? = nil,
    architectures: Set<String> = ["arm64"]
  ) -> FBLogicTestConfiguration {
    return FBLogicTestConfiguration(
      environment: env,
      workingDirectory: workDir,
      testBundlePath: bundlePath,
      waitForDebugger: waitForDebugger,
      timeout: timeout,
      testFilter: testFilter,
      mirroring: mirroring,
      coverageConfiguration: coverageConfiguration,
      binaryPath: binaryPath,
      logDirectoryPath: logDirectoryPath,
      architectures: architectures
    )
  }

  func testListTestConfigurationTestType() {
    let config = makeListConfig()
    XCTAssertEqual(config.testType, FBXCTestType.listTest)
  }

  func testListTestConfigurationProperties() {
    let env = ["KEY": "VALUE"]
    let config = makeListConfig(
      env: env,
      workDir: "/work",
      bundlePath: "/tests.xctest",
      runnerAppPath: "/runner.app",
      waitForDebugger: true,
      timeout: 200,
      architectures: ["arm64", "x86_64"]
    )
    XCTAssertEqual(config.processUnderTestEnvironment, env)
    XCTAssertEqual(config.workingDirectory, "/work")
    XCTAssertEqual(config.testBundlePath, "/tests.xctest")
    XCTAssertEqual(config.runnerAppPath, "/runner.app")
    XCTAssertTrue(config.waitForDebugger)
    XCTAssertEqual(config.architectures, Set(["arm64", "x86_64"]))
  }

  func testListTestConfigurationDescription() {
    let config = makeListConfig()
    let desc = config.description
    XCTAssertTrue(desc.contains("list-test"), "Description should contain test type")
    XCTAssertTrue(desc.contains("/bundle.xctest"), "Description should contain bundle path")
  }

  func testListTestConfigurationEquality() {
    let config1 = makeListConfig()
    let config2 = makeListConfig()
    XCTAssertEqual(config1, config2)
    XCTAssertEqual(config1.hash, config2.hash)
  }

  // MARK: FBTestManagerTestConfiguration

  func testManagerTestConfigurationApplicationTestType() {
    let config = FBTestManagerTestConfiguration(
      environment: [:],
      workingDirectory: "/tmp",
      testBundlePath: "/test.xctest",
      waitForDebugger: false,
      timeout: 300,
      runnerAppPath: "/runner.app",
      testTargetAppPath: nil,
      testFilter: nil,
      videoRecordingPath: nil,
      testArtifactsFilenameGlobs: nil,
      osLogPath: nil
    )
    XCTAssertEqual(config.testType, FBXCTestType.applicationTest)
  }

  func testManagerTestConfigurationUITestType() {
    let config = FBTestManagerTestConfiguration(
      environment: [:],
      workingDirectory: "/tmp",
      testBundlePath: "/test.xctest",
      waitForDebugger: false,
      timeout: 300,
      runnerAppPath: "/runner.app",
      testTargetAppPath: "/target.app",
      testFilter: nil,
      videoRecordingPath: nil,
      testArtifactsFilenameGlobs: nil,
      osLogPath: nil
    )
    XCTAssertEqual(config.testType, FBXCTestType.uiTest)
  }

  func testManagerTestConfigurationProperties() {
    let config = FBTestManagerTestConfiguration(
      environment: ["A": "B"],
      workingDirectory: "/work",
      testBundlePath: "/tests.xctest",
      waitForDebugger: true,
      timeout: 500,
      runnerAppPath: "/host.app",
      testTargetAppPath: "/target.app",
      testFilter: "MyClass/testMethod",
      videoRecordingPath: "/video.mp4",
      testArtifactsFilenameGlobs: ["*.png", "*.log"],
      osLogPath: "/os.log"
    )
    XCTAssertEqual(config.runnerAppPath, "/host.app")
    XCTAssertEqual(config.testTargetAppPath, "/target.app")
    XCTAssertEqual(config.testFilter, "MyClass/testMethod")
    XCTAssertEqual(config.videoRecordingPath, "/video.mp4")
    XCTAssertEqual(config.testArtifactsFilenameGlobs, ["*.png", "*.log"])
    XCTAssertEqual(config.osLogPath, "/os.log")
    XCTAssertTrue(config.waitForDebugger)
  }

  func testManagerTestConfigurationDescription() {
    let config = FBTestManagerTestConfiguration(
      environment: [:],
      workingDirectory: "/tmp",
      testBundlePath: "/test.xctest",
      waitForDebugger: false,
      timeout: 300,
      runnerAppPath: "/runner.app",
      testTargetAppPath: "/target.app",
      testFilter: "SomeFilter",
      videoRecordingPath: "/vid.mp4",
      testArtifactsFilenameGlobs: nil,
      osLogPath: nil
    )
    let desc = config.description
    XCTAssertTrue(desc.contains("ui-test"), "Description should contain test type")
    XCTAssertTrue(desc.contains("/runner.app"), "Description should contain runner path")
    XCTAssertTrue(desc.contains("/target.app"), "Description should contain target path")
    XCTAssertTrue(desc.contains("SomeFilter"), "Description should contain test filter")
  }

  // MARK: FBLogicTestConfiguration

  func testLogicTestConfigurationTestType() {
    let config = makeLogicConfig()
    XCTAssertEqual(config.testType, FBXCTestType.logicTest)
  }

  func testLogicTestConfigurationProperties() {
    let coverage = FBCodeCoverageConfiguration(
      directory: "/cov",
      format: .raw,
      enableContinuousCoverageCollection: true
    )
    let config = makeLogicConfig(
      env: ["FOO": "BAR"],
      workDir: "/work",
      bundlePath: "/logic.xctest",
      waitForDebugger: true,
      timeout: 250,
      testFilter: "TestClass/testMethod",
      mirroring: .fileLogs,
      coverageConfiguration: coverage,
      binaryPath: "/bin/test",
      logDirectoryPath: "/logs",
      architectures: ["x86_64", "arm64"]
    )
    XCTAssertEqual(config.testFilter, "TestClass/testMethod")
    XCTAssertEqual(config.mirroring, .fileLogs)
    XCTAssertNotNil(config.coverageConfiguration)
    XCTAssertEqual(config.coverageConfiguration?.coverageDirectory, "/cov")
    XCTAssertEqual(config.binaryPath, "/bin/test")
    XCTAssertEqual(config.logDirectoryPath, "/logs")
    XCTAssertEqual(config.architectures, Set(["x86_64", "arm64"]))
    XCTAssertTrue(config.waitForDebugger)
  }

  func testLogicTestConfigurationDescription() {
    let config = makeLogicConfig(testFilter: "MyFilter")
    let desc = config.description
    XCTAssertTrue(desc.contains("logic-test"), "Description should contain test type")
    XCTAssertTrue(desc.contains("MyFilter"), "Description should contain test filter")
  }

  func testLogicTestConfigurationMirroringCombined() {
    let config = makeLogicConfig(mirroring: [.fileLogs, .logger])
    XCTAssertTrue(config.mirroring.contains(.fileLogs))
    XCTAssertTrue(config.mirroring.contains(.logger))
  }

  // MARK: FBXCTestConfiguration base class

  func testBuildEnvironmentWithEntries() {
    let config = makeListConfig()
    let env = config.buildEnvironment(withEntries: ["CUSTOM_KEY": "custom_value"])
    XCTAssertEqual(env["CUSTOM_KEY"], "custom_value")
    XCTAssertNil(env["XCTestConfigurationFilePath"])
  }

  func testConfigurationDefaultTimeout() {
    let config = makeListConfig(timeout: 0)
    // When timeout is 0, should use default (500 normally, 1800 under TSAN)
    XCTAssertGreaterThan(config.testTimeout, 0)
  }

  func testConfigurationCopy() {
    let config = makeListConfig()
    let copied = config.copy() as! FBListTestConfiguration
    XCTAssertEqual(config, copied)
  }

  func testConfigurationInequalityAcrossSubclasses() {
    let listConfig = makeListConfig()
    let logicConfig = makeLogicConfig(architectures: ["x86_64"])
    // Different subclasses should not be equal even with same base properties
    XCTAssertFalse(listConfig.isEqual(logicConfig))
  }

  func testConfigurationDescription() {
    let config = makeLogicConfig()
    let desc = config.description
    XCTAssertTrue(desc.contains("logic-test"), "Description should contain the test type")
    XCTAssertTrue(desc.contains("/logic.xctest"), "Description should contain the test bundle path")
  }
}

// MARK: - XCTestBootstrapError Tests

final class XCTestBootstrapErrorTransientTests: XCTestCase {

  func testErrorDomainConstants() {
    XCTAssertEqual(XCTestBootstrapErrorDomain, "com.facebook.XCTestBootstrap")
    XCTAssertEqual(FBTestErrorDomain, "com.facebook.FBTestError")
  }

  func testErrorCodeConstants() {
    XCTAssertEqual(XCTestBootstrapErrorCodeStartupFailure, 0x3)
    XCTAssertEqual(XCTestBootstrapErrorCodeLostConnection, 0x4)
    XCTAssertEqual(XCTestBootstrapErrorCodeStartupTimeout, 0x5)
  }
}

// MARK: - FBXCTestType Constants Tests

final class FBXCTestTypeConstantsTransientTests: XCTestCase {

  func testTypeConstants() {
    XCTAssertEqual(FBXCTestType.applicationTest.rawValue, "application-test")
    XCTAssertEqual(FBXCTestType.logicTest.rawValue, "logic-test")
    XCTAssertEqual(FBXCTestType.listTest.rawValue, "list-test")
    XCTAssertEqual(FBXCTestType.uiTest.rawValue, "ui-test")
  }
}
