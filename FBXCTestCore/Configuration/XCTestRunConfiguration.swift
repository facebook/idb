/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MARK: - JSON Keys

private let KeyEnvironment = "environment"
private let KeyListTestsOnly = "list_only"
private let KeyOSLogPath = "os_log_path"
private let KeyRunnerAppPath = "test_host_path"
private let KeyRunnerTargetPath = "test_target_path"
private let KeyTestArtifactsFilenameGlobs = "test_artifacts_filename_globs"
private let KeyTestBundlePath = "test_bundle_path"
private let KeyTestFilter = "test_filter"
private let KeyTestMirror = "test_mirror"
private let KeyTestTimeout = "test_timeout"
private let KeyTestType = "test_type"
private let KeyVideoRecordingPath = "video_recording_path"
private let KeyWaitForDebugger = "wait_for_debugger"
private let KeyWorkingDirectory = "working_directory"

private let kDefaultTimeoutValue: TimeInterval = 500

// MARK: - Test Types

/// The type of an xctest execution, as reported in ocunit-shim events.
struct XCTestType: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let applicationTest = XCTestType(rawValue: "application-test")
  public static let logicTest = XCTestType(rawValue: "logic-test")
  public static let listTest = XCTestType(rawValue: "list-test")
  public static let uiTest = XCTestType(rawValue: "ui-test")
}

/// Where a logic test's output is mirrored to, in addition to the reporter.
public struct LogicTestMirrorLogs: OptionSet, Sendable {
  public let rawValue: UInt

  public init(rawValue: UInt) {
    self.rawValue = rawValue
  }

  public static let fileLogs = LogicTestMirrorLogs(rawValue: 1 << 0)
  public static let logger = LogicTestMirrorLogs(rawValue: 1 << 1)
}

// MARK: - XCTestRunConfiguration

private func resolveTestTimeout(_ timeout: TimeInterval) -> TimeInterval {
  if let timeoutFromEnv = ProcessInfo.processInfo.environment["FB_TEST_TIMEOUT"],
    let envTimeout = TimeInterval(timeoutFromEnv)
  {
    return envTimeout
  }
  return timeout > 0 ? timeout : kDefaultTimeoutValue
}

/// The configuration shared by every kind of xctest run.
protocol XCTestRunConfiguration: Sendable {
  var processUnderTestEnvironment: [String: String] { get }
  var workingDirectory: String { get }
  var testBundlePath: String { get }
  var waitForDebugger: Bool { get }
  var testTimeout: TimeInterval { get }
  var testType: XCTestType { get }
  func jsonSerializableRepresentation() -> [String: Any]
}

extension XCTestRunConfiguration {

  func buildEnvironment(withEntries entries: [String: String]) -> [String: String] {
    var parentEnvironment = ProcessInfo.processInfo.environment
    parentEnvironment.removeValue(forKey: "XCTestConfigurationFilePath")

    var environmentOverrides: [String: String] = [:]
    let xctoolTestEnvPrefix = "XCTOOL_TEST_ENV_"
    for (key, value) in parentEnvironment {
      if key.hasPrefix(xctoolTestEnvPrefix) {
        let childKey = String(key.dropFirst(xctoolTestEnvPrefix.count))
        environmentOverrides[childKey] = value
      }
    }
    for (key, value) in entries {
      environmentOverrides[key] = value
    }
    var environment = parentEnvironment
    for (key, value) in environmentOverrides {
      environment[key] = value
    }
    return environment
  }

  var baseJSONSerializableRepresentation: [String: Any] {
    [
      KeyEnvironment: processUnderTestEnvironment,
      KeyWorkingDirectory: workingDirectory,
      KeyTestBundlePath: testBundlePath,
      KeyTestType: testType.rawValue,
      KeyListTestsOnly: false,
      KeyWaitForDebugger: waitForDebugger,
      KeyTestTimeout: testTimeout,
    ]
  }

  var jsonDescription: String {
    guard let data = try? JSONSerialization.data(withJSONObject: jsonSerializableRepresentation(), options: []),
      let string = String(data: data, encoding: .utf8)
    else {
      return String(describing: type(of: self))
    }
    return string
  }
}

// MARK: - ListTestConfiguration

public struct ListTestConfiguration: XCTestRunConfiguration, Hashable, CustomStringConvertible {

  public let processUnderTestEnvironment: [String: String]
  public let workingDirectory: String
  public let testBundlePath: String
  public let waitForDebugger: Bool
  public let testTimeout: TimeInterval
  public let architectures: Set<String>
  public let runnerAppPath: String?

  public static func configuration(withEnvironment environment: [String: String], workingDirectory: String, testBundlePath: String, runnerAppPath: String?, waitForDebugger: Bool, timeout: TimeInterval, architectures: Set<String>) -> ListTestConfiguration {
    ListTestConfiguration(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, runnerAppPath: runnerAppPath, waitForDebugger: waitForDebugger, timeout: timeout, architectures: architectures)
  }

  public init(environment: [String: String], workingDirectory: String, testBundlePath: String, runnerAppPath: String?, waitForDebugger: Bool, timeout: TimeInterval, architectures: Set<String>) {
    self.processUnderTestEnvironment = environment
    self.workingDirectory = workingDirectory
    self.testBundlePath = testBundlePath
    self.waitForDebugger = waitForDebugger
    self.testTimeout = resolveTestTimeout(timeout)
    self.runnerAppPath = runnerAppPath
    self.architectures = architectures
  }

  var testType: XCTestType {
    XCTestType.listTest
  }

  public var description: String {
    jsonDescription
  }

  func jsonSerializableRepresentation() -> [String: Any] {
    var json = baseJSONSerializableRepresentation
    json[KeyListTestsOnly] = true
    json[KeyRunnerAppPath] = runnerAppPath ?? NSNull()
    return json
  }
}

// MARK: - TestManagerTestConfiguration

struct TestManagerTestConfiguration: XCTestRunConfiguration, CustomStringConvertible {

  let processUnderTestEnvironment: [String: String]
  let workingDirectory: String
  let testBundlePath: String
  let waitForDebugger: Bool
  let testTimeout: TimeInterval
  let runnerAppPath: String
  let testTargetAppPath: String?
  let testFilter: String?
  let osLogPath: String?
  let videoRecordingPath: String?
  let testArtifactsFilenameGlobs: [String]?

  static func configuration(withEnvironment environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, runnerAppPath: String, testTargetAppPath: String?, testFilter: String?, videoRecordingPath: String?, testArtifactsFilenameGlobs: [String]?, osLogPath: String?) -> TestManagerTestConfiguration {
    TestManagerTestConfiguration(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout, runnerAppPath: runnerAppPath, testTargetAppPath: testTargetAppPath, testFilter: testFilter, videoRecordingPath: videoRecordingPath, testArtifactsFilenameGlobs: testArtifactsFilenameGlobs, osLogPath: osLogPath)
  }

  init(environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, runnerAppPath: String, testTargetAppPath: String?, testFilter: String?, videoRecordingPath: String?, testArtifactsFilenameGlobs: [String]?, osLogPath: String?) {
    self.processUnderTestEnvironment = environment
    self.workingDirectory = workingDirectory
    self.testBundlePath = testBundlePath
    self.waitForDebugger = waitForDebugger
    self.testTimeout = resolveTestTimeout(timeout)
    self.runnerAppPath = runnerAppPath
    self.testTargetAppPath = testTargetAppPath
    self.testFilter = testFilter
    self.videoRecordingPath = videoRecordingPath
    self.testArtifactsFilenameGlobs = testArtifactsFilenameGlobs
    self.osLogPath = osLogPath
  }

  var testType: XCTestType {
    testTargetAppPath != nil ? XCTestType.uiTest : XCTestType.applicationTest
  }

  var description: String {
    jsonDescription
  }

  func jsonSerializableRepresentation() -> [String: Any] {
    var json = baseJSONSerializableRepresentation
    json[KeyRunnerAppPath] = runnerAppPath
    if let testTargetAppPath { json[KeyRunnerTargetPath] = testTargetAppPath }
    if let testFilter { json[KeyTestFilter] = testFilter }
    if let videoRecordingPath { json[KeyVideoRecordingPath] = videoRecordingPath }
    if let testArtifactsFilenameGlobs { json[KeyTestArtifactsFilenameGlobs] = testArtifactsFilenameGlobs }
    if let osLogPath { json[KeyOSLogPath] = osLogPath }
    return json
  }
}

// MARK: - LogicTestConfiguration

public struct LogicTestConfiguration: XCTestRunConfiguration, CustomStringConvertible {

  public let processUnderTestEnvironment: [String: String]
  public let workingDirectory: String
  public let testBundlePath: String
  public let waitForDebugger: Bool
  public let testTimeout: TimeInterval
  public let testFilter: String?
  public let mirroring: LogicTestMirrorLogs
  public let coverageConfiguration: CodeCoverageConfiguration?
  public let binaryPath: String?
  public let logDirectoryPath: String?
  public let architectures: Set<String>
  public let injectLibraries: [String]

  public static func configuration(withEnvironment environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, testFilter: String?, mirroring: LogicTestMirrorLogs, coverageConfiguration: CodeCoverageConfiguration?, binaryPath: String?, logDirectoryPath: String?, architectures: Set<String>) -> LogicTestConfiguration {
    LogicTestConfiguration(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout, testFilter: testFilter, mirroring: mirroring, coverageConfiguration: coverageConfiguration, binaryPath: binaryPath, logDirectoryPath: logDirectoryPath, architectures: architectures)
  }

  public init(environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, testFilter: String?, mirroring: LogicTestMirrorLogs, coverageConfiguration: CodeCoverageConfiguration?, binaryPath: String?, logDirectoryPath: String?, architectures: Set<String>, injectLibraries: [String] = []) {
    self.processUnderTestEnvironment = environment
    self.workingDirectory = workingDirectory
    self.testBundlePath = testBundlePath
    self.waitForDebugger = waitForDebugger
    self.testTimeout = resolveTestTimeout(timeout)
    self.testFilter = testFilter
    self.mirroring = mirroring
    self.coverageConfiguration = coverageConfiguration
    self.binaryPath = binaryPath
    self.logDirectoryPath = logDirectoryPath
    self.architectures = architectures
    self.injectLibraries = injectLibraries
  }

  var testType: XCTestType {
    XCTestType.logicTest
  }

  public var description: String {
    jsonDescription
  }

  func jsonSerializableRepresentation() -> [String: Any] {
    var json = baseJSONSerializableRepresentation
    json[KeyTestFilter] = testFilter ?? NSNull()
    return json
  }
}
