/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import XCTestBootstrap

// MARK: - FBCodeCoverageConfiguration Tests

final class FBCodeCoverageConfigurationTransientTests: XCTestCase {

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

// MARK: - FBTestManagerResultSummary Tests

final class FBTestManagerResultSummaryTransientTests: XCTestCase {

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

  func testLogicTestConfigurationDescription() {
    let config = makeLogicConfig(testFilter: "MyFilter")
    let desc = config.description
    XCTAssertTrue(desc.contains("logic-test"), "Description should contain test type")
    XCTAssertTrue(desc.contains("MyFilter"), "Description should contain test filter")
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
    XCTAssertFalse(listConfig.isEqual(logicConfig))
  }

  func testConfigurationDescription() {
    let config = makeLogicConfig()
    let desc = config.description
    XCTAssertTrue(desc.contains("logic-test"), "Description should contain the test type")
    XCTAssertTrue(desc.contains("/logic.xctest"), "Description should contain the test bundle path")
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
