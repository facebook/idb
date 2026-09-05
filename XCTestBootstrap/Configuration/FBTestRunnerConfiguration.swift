/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let kEnvShimStartXCTest = "SHIMULATOR_START_XCTEST"
private let kEnvWaitForDebugger = "XCTOOL_WAIT_FOR_DEBUGGER"
private let kEnvLLVMProfileFile = "LLVM_PROFILE_FILE"
private let kEnvLogDirectoryPath = "LOG_DIRECTORY_PATH"

/// The ways runner-configuration preparation can fail, as data rather than assembled strings.
public enum FBTestRunnerConfigurationError: Error, LocalizedError {
  case codesignCheckFailed(bundlePath: String, underlying: Error)
  case testBundlePreparationFailed(underlying: Error)
  case testConfigurationPreparationFailed(underlying: Error)

  public var errorDescription: String? {
    switch self {
    case let .codesignCheckFailed(bundlePath, _):
      return "Could not determine bundle at path '\(bundlePath)' is codesigned and codesigning is required"
    case .testBundlePreparationFailed:
      return "Failed to prepare test bundle"
    case .testConfigurationPreparationFailed:
      return "Failed to prepare test configuration"
    }
  }
}

public struct FBTestRunnerConfiguration {

  // MARK: Properties

  public let sessionIdentifier: UUID
  public let testRunner: FBBundleDescriptor
  public let launchEnvironment: [String: String]
  public let testedApplicationAdditionalEnvironment: [String: String]
  public let testConfiguration: FBTestConfiguration

  public var launchArguments: [String] {
    [
      "-NSTreatUnknownArgumentsAsOpen", "NO",
      "-ApplePersistenceIgnoreState", "YES",
    ]
  }

  // MARK: Initializers

  public init(sessionIdentifier: UUID, testRunner: FBBundleDescriptor, launchEnvironment: [String: String], testedApplicationAdditionalEnvironment: [String: String], testConfiguration: FBTestConfiguration) {
    self.sessionIdentifier = sessionIdentifier
    self.testRunner = testRunner
    self.launchEnvironment = launchEnvironment
    self.testedApplicationAdditionalEnvironment = testedApplicationAdditionalEnvironment
    self.testConfiguration = testConfiguration
  }

  // MARK: Public

  public static func prepareConfiguration(withTarget target: FBiOSTarget & ApplicationCommands & XCTestExtendedCommands, testLaunchConfiguration: FBTestLaunchConfiguration, workingDirectory: String, codesign: FBCodesignProvider?) async throws -> FBTestRunnerConfiguration {
    if let codesign {
      do {
        _ = try await bridgeFBFuture(codesign.cdHashForBundle(atPath: testLaunchConfiguration.testBundle.path))
      } catch {
        throw FBTestRunnerConfigurationError.codesignCheckFailed(bundlePath: testLaunchConfiguration.testBundle.path, underlying: error)
      }
    }
    return try await prepareConfigurationAfterCodesignatureCheck(withTarget: target, testLaunchConfiguration: testLaunchConfiguration, workingDirectory: workingDirectory)
  }

  public static func launchEnvironment(withHostApplication hostApplication: FBBundleDescriptor, hostApplicationAdditionalEnvironment: [String: String], testBundle: FBBundleDescriptor, testConfigurationPath: String, frameworkSearchPaths: [String]) -> [String: String] {
    var environmentVariables = hostApplicationAdditionalEnvironment
    let frameworkSearchPath = frameworkSearchPaths.joined(separator: ":")
    environmentVariables["AppTargetLocation"] = hostApplication.binary?.path ?? ""
    environmentVariables["DYLD_FALLBACK_FRAMEWORK_PATH"] = frameworkSearchPath.isEmpty ? "" : frameworkSearchPath
    environmentVariables["DYLD_FALLBACK_LIBRARY_PATH"] = frameworkSearchPath.isEmpty ? "" : frameworkSearchPath
    environmentVariables["OBJC_DISABLE_GC"] = "YES"
    environmentVariables["TestBundleLocation"] = testBundle.path
    environmentVariables["XCODE_DBG_XPC_EXCLUSIONS"] = "com.apple.dt.xctestSymbolicator"
    environmentVariables["XCTestConfigurationFilePath"] = testConfigurationPath
    return addAdditionalEnvironmentVariables(environmentVariables)
  }

  // MARK: Private

  private static func addAdditionalEnvironmentVariables(_ currentEnvironmentVariables: [String: String]) -> [String: String] {
    let prefix = "CUSTOM_"
    var envs = currentEnvironmentVariables
    for (key, value) in ProcessInfo.processInfo.environment {
      if key.hasPrefix(prefix) {
        envs[String(key.dropFirst(prefix.count))] = value
      }
    }
    return envs
  }

  private static func prepareConfigurationAfterCodesignatureCheck(withTarget target: FBiOSTarget & ApplicationCommands & XCTestExtendedCommands, testLaunchConfiguration: FBTestLaunchConfiguration, workingDirectory: String) async throws -> FBTestRunnerConfiguration {
    let runtimeRoot = await target.runtimeRootDirectory
    let platformRoot = await target.platformRootDirectory

    // This directory will contain XCTest.framework, built for the target platform.
    let platformDeveloperFrameworksPath = (platformRoot as NSString).appendingPathComponent("Developer/Library/Frameworks")
    let developerLibraryPath = (runtimeRoot as NSString).appendingPathComponent("Developer/Library")
    // Contains other frameworks, depended on by XCTest and Instruments
    let xcTestFrameworksPaths = [
      (developerLibraryPath as NSString).appendingPathComponent("Frameworks"),
      (developerLibraryPath as NSString).appendingPathComponent("PrivateFrameworks"),
      platformDeveloperFrameworksPath,
    ]

    let automationFrameworkPath = (developerLibraryPath as NSString).appendingPathComponent("PrivateFrameworks/XCTAutomationSupport.framework")
    let automationFrameworkPathOrNil: String? = FileManager.default.fileExists(atPath: automationFrameworkPath) ? automationFrameworkPath : nil

    var testedApplicationAdditionalEnvironment: [String: String] = [:]
    let xctTargetBootstrapInjectPath = (platformRoot as NSString).appendingPathComponent("Developer/usr/lib/libXCTTargetBootstrapInject.dylib")
    // Xcode > 12.5 does not have this file neither requires its injection in the target test app.
    if FileManager.default.fileExists(atPath: xctTargetBootstrapInjectPath) {
      testedApplicationAdditionalEnvironment["DYLD_INSERT_LIBRARIES"] = xctTargetBootstrapInjectPath
    }

    var testApplicationDependencies: [String: String]?
    if let identifier = testLaunchConfiguration.targetApplicationBundle?.identifier,
      let path = testLaunchConfiguration.targetApplicationBundle?.path
    {
      testApplicationDependencies = [identifier: path]
    }

    let sessionIdentifier = UUID()
    let testBundle: FBBundleDescriptor
    do {
      testBundle = try FBBundleDescriptor.bundle(fromPath: testLaunchConfiguration.testBundle.path)
    } catch {
      throw FBTestRunnerConfigurationError.testBundlePreparationFailed(underlying: error)
    }

    let testConfiguration: FBTestConfiguration
    do {
      testConfiguration = try FBTestConfiguration(
        byWritingToFileWithSessionIdentifier: sessionIdentifier,
        moduleName: testBundle.name,
        testBundlePath: testBundle.path,
        uiTesting: testLaunchConfiguration.shouldInitializeUITesting,
        testsToRun: testLaunchConfiguration.testsToRun,
        testsToSkip: testLaunchConfiguration.testsToSkip,
        targetApplicationPath: testLaunchConfiguration.targetApplicationBundle?.path,
        targetApplicationBundleID: testLaunchConfiguration.targetApplicationBundle?.identifier,
        testApplicationDependencies: testApplicationDependencies,
        automationFrameworkPath: automationFrameworkPathOrNil,
        reportActivities: testLaunchConfiguration.reportActivities
      )
    } catch {
      throw FBTestRunnerConfigurationError.testConfigurationPreparationFailed(underlying: error)
    }

    let hostApplication = try await target.installedApplication(bundleID: testLaunchConfiguration.applicationLaunchConfiguration.bundleID)
    let shimPath = try await target.extendedTestShim()

    var hostApplicationAdditionalEnvironment: [String: String] = [:]
    hostApplicationAdditionalEnvironment[kEnvShimStartXCTest] = "1"
    hostApplicationAdditionalEnvironment["DYLD_INSERT_LIBRARIES"] = shimPath
    hostApplicationAdditionalEnvironment[kEnvWaitForDebugger] = testLaunchConfiguration.applicationLaunchConfiguration.waitForDebugger ? "YES" : "NO"

    if let coverageDirectoryPath = testLaunchConfiguration.coverageDirectoryPath {
      let continuousCoverageCollectionMode = testLaunchConfiguration.shouldEnableContinuousCoverageCollection ? "%c" : ""
      let hostCoverageFile = "coverage_\(hostApplication.bundle.identifier)\(continuousCoverageCollectionMode).profraw"
      let hostCoveragePath = (coverageDirectoryPath as NSString).appendingPathComponent(hostCoverageFile)
      hostApplicationAdditionalEnvironment[kEnvLLVMProfileFile] = hostCoveragePath

      if let targetBundle = testLaunchConfiguration.targetApplicationBundle {
        let targetCoverageFile = "coverage_\(targetBundle.identifier)\(continuousCoverageCollectionMode).profraw"
        let targetAppCoveragePath = (coverageDirectoryPath as NSString).appendingPathComponent(targetCoverageFile)
        testedApplicationAdditionalEnvironment[kEnvLLVMProfileFile] = targetAppCoveragePath
      }
    }

    if let logDirectoryPath = testLaunchConfiguration.logDirectoryPath {
      hostApplicationAdditionalEnvironment[kEnvLogDirectoryPath] = logDirectoryPath
    }

    let frameworkSearchPaths = xcTestFrameworksPaths + [(hostApplication.bundle.path as NSString).appendingPathComponent("Frameworks")]

    let launchEnvironment = FBTestRunnerConfiguration.launchEnvironment(
      withHostApplication: hostApplication.bundle,
      hostApplicationAdditionalEnvironment: hostApplicationAdditionalEnvironment,
      testBundle: testBundle,
      testConfigurationPath: testConfiguration.path,
      frameworkSearchPaths: frameworkSearchPaths
    )

    return FBTestRunnerConfiguration(
      sessionIdentifier: sessionIdentifier,
      testRunner: hostApplication.bundle,
      launchEnvironment: launchEnvironment,
      testedApplicationAdditionalEnvironment: testedApplicationAdditionalEnvironment,
      testConfiguration: testConfiguration
    )
  }
}
