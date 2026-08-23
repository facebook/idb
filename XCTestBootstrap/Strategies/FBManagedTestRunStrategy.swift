/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The way a managed run fails before starting, as data rather than an assembled string.
public enum FBManagedTestRunError: Error, LocalizedError {
  case frameworkLoadingFailed(underlying: Error)

  public var errorDescription: String? {
    switch self {
    case let .frameworkLoadingFailed(underlying):
      return underlying.localizedDescription
    }
  }
}

public final class FBManagedTestRunStrategy {

  public static func runToCompletion(withTarget target: any FBiOSTarget & ApplicationCommands & XCTestExtendedCommands & CrashLogCommands, configuration: FBTestLaunchConfiguration, codesign: FBCodesignProvider?, workingDirectory: String, reporter: FBXCTestReporter, logger: FBControlCoreLogger) async throws {
    do {
      try XCTestBootstrapFrameworkLoader.allDependentFrameworks.loadPrivateFrameworks(target.logger)
    } catch {
      throw FBManagedTestRunError.frameworkLoadingFailed(underlying: error)
    }

    let runnerConfiguration = try await FBTestRunnerConfiguration.prepareConfiguration(
      withTarget: target,
      testLaunchConfiguration: configuration,
      workingDirectory: workingDirectory,
      codesign: codesign
    )

    let testHostLaunchConfiguration = prepareApplicationLaunchConfiguration(configuration.applicationLaunchConfiguration, withTestRunnerConfiguration: runnerConfiguration)

    let context = FBTestManagerContext(
      sessionIdentifier: runnerConfiguration.sessionIdentifier,
      timeout: configuration.timeout,
      testHostLaunchConfiguration: testHostLaunchConfiguration,
      testedApplicationAdditionalEnvironment: runnerConfiguration.testedApplicationAdditionalEnvironment,
      testConfiguration: runnerConfiguration.testConfiguration
    )

    try await FBTestManagerAPIMediator.connectAndRunUntilCompletion(
      with: context,
      target: target,
      reporter: reporter,
      logger: logger
    )
  }

  private static func prepareApplicationLaunchConfiguration(_ applicationLaunchConfiguration: FBApplicationLaunchConfiguration, withTestRunnerConfiguration testRunnerConfiguration: FBTestRunnerConfiguration) -> FBApplicationLaunchConfiguration {
    FBApplicationLaunchConfiguration(
      bundleID: testRunnerConfiguration.testRunner.identifier,
      bundleName: testRunnerConfiguration.testRunner.identifier,
      arguments: arguments(fromConfiguration: testRunnerConfiguration, attributes: applicationLaunchConfiguration.arguments),
      environment: environment(fromConfiguration: testRunnerConfiguration, environment: applicationLaunchConfiguration.environment),
      waitForDebugger: applicationLaunchConfiguration.waitForDebugger,
      io: applicationLaunchConfiguration.io,
      launchMode: .relaunchIfRunning
    )
  }

  private static func arguments(fromConfiguration configuration: FBTestRunnerConfiguration, attributes: [String]) -> [String] {
    configuration.launchArguments + attributes
  }

  private static func environment(fromConfiguration configuration: FBTestRunnerConfiguration, environment: [String: String]) -> [String: String] {
    var mEnvironment = configuration.launchEnvironment
    for (key, value) in environment {
      mEnvironment[key] = value
    }
    return mEnvironment
  }
}
