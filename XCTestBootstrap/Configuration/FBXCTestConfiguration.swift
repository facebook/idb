/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MARK: JSON Keys

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

// MARK: Defaults

private let kDefaultTimeoutValue: TimeInterval = 500

// MARK: - Test Types

/// The type of an xctest execution, as reported in ocunit-shim events.
public struct FBXCTestType: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let applicationTest = FBXCTestType(rawValue: "application-test")
  public static let logicTest = FBXCTestType(rawValue: "logic-test")
  public static let listTest = FBXCTestType(rawValue: "list-test")
  public static let uiTest = FBXCTestType(rawValue: "ui-test")
}

/// Where a logic test's output is mirrored to, in addition to the reporter.
public struct FBLogicTestMirrorLogs: OptionSet, Sendable {
  public let rawValue: UInt

  public init(rawValue: UInt) {
    self.rawValue = rawValue
  }

  public static let fileLogs = FBLogicTestMirrorLogs(rawValue: 1 << 0)
  public static let logger = FBLogicTestMirrorLogs(rawValue: 1 << 1)
}

// MARK: - FBXCTestConfiguration

public class FBXCTestConfiguration: NSObject, NSCopying {

  public let processUnderTestEnvironment: [String: String]
  public let workingDirectory: String
  public let testBundlePath: String
  public let waitForDebugger: Bool
  public let testTimeout: TimeInterval

  var testType: FBXCTestType {
    fatalError("-[\(type(of: self)) testType] is abstract and should be overridden")
  }

  public init(environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval) {
    self.processUnderTestEnvironment = environment
    self.workingDirectory = workingDirectory
    self.testBundlePath = testBundlePath
    self.waitForDebugger = waitForDebugger

    if let timeoutFromEnv = ProcessInfo.processInfo.environment["FB_TEST_TIMEOUT"],
      let envTimeout = TimeInterval(timeoutFromEnv)
    {
      self.testTimeout = envTimeout
    } else {
      self.testTimeout = timeout > 0 ? timeout : kDefaultTimeoutValue
    }
    super.init()
  }

  // MARK: NSObject

  public override var description: String {
    guard let data = try? JSONSerialization.data(withJSONObject: jsonSerializableRepresentation(), options: []) else {
      return super.description
    }
    return String(data: data, encoding: .utf8) ?? super.description
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBXCTestConfiguration else { return false }
    guard type(of: other) == type(of: self) else { return false }
    return processUnderTestEnvironment == other.processUnderTestEnvironment
      && workingDirectory == other.workingDirectory
      && testBundlePath == other.testBundlePath
      && testType.rawValue == other.testType.rawValue
      && waitForDebugger == other.waitForDebugger
      && testTimeout == other.testTimeout
  }

  public override var hash: Int {
    (processUnderTestEnvironment as NSDictionary).hash ^ (workingDirectory as NSString).hash ^ (testBundlePath as NSString).hash ^ (testType.rawValue as NSString).hash ^ (waitForDebugger ? 1 : 0) ^ Int(testTimeout)
  }

  // MARK: Public

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

  // MARK: JSON

  func jsonSerializableRepresentation() -> [String: Any] {
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

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    self
  }
}

// MARK: - FBListTestConfiguration

public final class FBListTestConfiguration: FBXCTestConfiguration {

  public let architectures: Set<String>
  public let runnerAppPath: String?

  public static func configuration(withEnvironment environment: [String: String], workingDirectory: String, testBundlePath: String, runnerAppPath: String?, waitForDebugger: Bool, timeout: TimeInterval, architectures: Set<String>) -> FBListTestConfiguration {
    FBListTestConfiguration(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, runnerAppPath: runnerAppPath, waitForDebugger: waitForDebugger, timeout: timeout, architectures: architectures)
  }

  public init(environment: [String: String], workingDirectory: String, testBundlePath: String, runnerAppPath: String?, waitForDebugger: Bool, timeout: TimeInterval, architectures: Set<String>) {
    self.runnerAppPath = runnerAppPath
    self.architectures = architectures
    super.init(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout)
  }

  override var testType: FBXCTestType {
    FBXCTestType.listTest
  }

  override func jsonSerializableRepresentation() -> [String: Any] {
    var json = super.jsonSerializableRepresentation()
    json[KeyListTestsOnly] = true
    json[KeyRunnerAppPath] = runnerAppPath ?? NSNull()
    return json
  }
}

// MARK: - FBTestManagerTestConfiguration

public final class FBTestManagerTestConfiguration: FBXCTestConfiguration {

  public let runnerAppPath: String
  public let testTargetAppPath: String?
  public let testFilter: String?
  public let osLogPath: String?
  public let videoRecordingPath: String?
  public let testArtifactsFilenameGlobs: [String]?

  public static func configuration(withEnvironment environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, runnerAppPath: String, testTargetAppPath: String?, testFilter: String?, videoRecordingPath: String?, testArtifactsFilenameGlobs: [String]?, osLogPath: String?) -> FBTestManagerTestConfiguration {
    FBTestManagerTestConfiguration(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout, runnerAppPath: runnerAppPath, testTargetAppPath: testTargetAppPath, testFilter: testFilter, videoRecordingPath: videoRecordingPath, testArtifactsFilenameGlobs: testArtifactsFilenameGlobs, osLogPath: osLogPath)
  }

  public init(environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, runnerAppPath: String, testTargetAppPath: String?, testFilter: String?, videoRecordingPath: String?, testArtifactsFilenameGlobs: [String]?, osLogPath: String?) {
    self.runnerAppPath = runnerAppPath
    self.testTargetAppPath = testTargetAppPath
    self.testFilter = testFilter
    self.videoRecordingPath = videoRecordingPath
    self.testArtifactsFilenameGlobs = testArtifactsFilenameGlobs
    self.osLogPath = osLogPath
    super.init(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout)
  }

  override var testType: FBXCTestType {
    testTargetAppPath != nil ? FBXCTestType.uiTest : FBXCTestType.applicationTest
  }

  override func jsonSerializableRepresentation() -> [String: Any] {
    var json = super.jsonSerializableRepresentation()
    json[KeyRunnerAppPath] = runnerAppPath
    if let testTargetAppPath { json[KeyRunnerTargetPath] = testTargetAppPath }
    if let testFilter { json[KeyTestFilter] = testFilter }
    if let videoRecordingPath { json[KeyVideoRecordingPath] = videoRecordingPath }
    if let testArtifactsFilenameGlobs { json[KeyTestArtifactsFilenameGlobs] = testArtifactsFilenameGlobs }
    if let osLogPath { json[KeyOSLogPath] = osLogPath }
    return json
  }
}

// MARK: - FBLogicTestConfiguration

public final class FBLogicTestConfiguration: FBXCTestConfiguration {

  public let testFilter: String?
  public let mirroring: FBLogicTestMirrorLogs
  public let coverageConfiguration: FBCodeCoverageConfiguration?
  public let binaryPath: String?
  public let logDirectoryPath: String?
  public let architectures: Set<String>
  public let injectLibraries: [String]

  public static func configuration(withEnvironment environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, testFilter: String?, mirroring: FBLogicTestMirrorLogs, coverageConfiguration: FBCodeCoverageConfiguration?, binaryPath: String?, logDirectoryPath: String?, architectures: Set<String>) -> FBLogicTestConfiguration {
    FBLogicTestConfiguration(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout, testFilter: testFilter, mirroring: mirroring, coverageConfiguration: coverageConfiguration, binaryPath: binaryPath, logDirectoryPath: logDirectoryPath, architectures: architectures)
  }

  public init(environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, testFilter: String?, mirroring: FBLogicTestMirrorLogs, coverageConfiguration: FBCodeCoverageConfiguration?, binaryPath: String?, logDirectoryPath: String?, architectures: Set<String>, injectLibraries: [String] = []) {
    self.testFilter = testFilter
    self.mirroring = mirroring
    self.coverageConfiguration = coverageConfiguration
    self.binaryPath = binaryPath
    self.logDirectoryPath = logDirectoryPath
    self.architectures = architectures
    self.injectLibraries = injectLibraries
    super.init(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout)
  }

  override var testType: FBXCTestType {
    FBXCTestType.logicTest
  }

  override func jsonSerializableRepresentation() -> [String: Any] {
    var json = super.jsonSerializableRepresentation()
    json[KeyTestFilter] = testFilter ?? NSNull()
    return json
  }
}
