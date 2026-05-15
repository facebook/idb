/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc public final class FBManagedTestRunStrategy: NSObject {

  @objc public static func runToCompletion(withTarget target: FBiOSTarget & FBXCTestExtendedCommands & FBApplicationCommands, configuration: FBTestLaunchConfiguration, codesign: FBCodesignProvider?, workingDirectory: String, reporter: FBXCTestReporter, logger: FBControlCoreLogger) -> FBFuture<NSNull> {
    do {
      try XCTestBootstrapFrameworkLoader.allDependentFrameworks.loadPrivateFrameworks(target.logger)
    } catch {
      return unsafeBitCast(XCTestBootstrapError.describe(error.localizedDescription).failFuture(), to: FBFuture<NSNull>.self)
    }

    let applicationLaunchConfiguration = configuration.applicationLaunchConfiguration

    // FBTestRunnerConfiguration.prepareConfiguration is a Swift method that
    // requires the Async* protocol composition. FBSimulator and FBMacDevice
    // both conform to these protocols in addition to the legacy ones declared
    // in this function's signature, so the cast is safe at runtime.
    // swiftlint:disable:next force_cast
    let asyncTarget = target as! any FBiOSTarget & AsyncApplicationCommands & AsyncXCTestExtendedCommands
    let prepareFuture: FBFuture<AnyObject> = unsafeBitCast(
      FBTestRunnerConfiguration.prepareConfiguration(
        withTarget: asyncTarget,
        testLaunchConfiguration: configuration,
        workingDirectory: workingDirectory,
        codesign: codesign
      ),
      to: FBFuture<AnyObject>.self
    )

    return unsafeBitCast(
      prepareFuture
        .onQueue(
          target.workQueue,
          fmap: { runnerConfigObj -> FBFuture<AnyObject> in
            let runnerConfiguration = runnerConfigObj as! FBTestRunnerConfiguration

            let testHostLaunchConfiguration = FBManagedTestRunStrategy.prepareApplicationLaunchConfiguration(applicationLaunchConfiguration, withTestRunnerConfiguration: runnerConfiguration)

            let context = FBTestManagerContext(
              sessionIdentifier: runnerConfiguration.sessionIdentifier,
              timeout: configuration.timeout,
              testHostLaunchConfiguration: testHostLaunchConfiguration,
              testedApplicationAdditionalEnvironment: runnerConfiguration.testedApplicationAdditionalEnvironment,
              testConfiguration: runnerConfiguration.testConfiguration
            )

            return unsafeBitCast(
              FBTestManagerAPIMediator.connectAndRunUntilCompletion(
                with: context,
                target: target,
                reporter: reporter,
                logger: logger
              ),
              to: FBFuture<AnyObject>.self
            )
          }),
      to: FBFuture<NSNull>.self
    )
  }

  private static func prepareApplicationLaunchConfiguration(_ applicationLaunchConfiguration: FBApplicationLaunchConfiguration, withTestRunnerConfiguration testRunnerConfiguration: FBTestRunnerConfiguration) -> FBApplicationLaunchConfiguration {
    return FBApplicationLaunchConfiguration(
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
    return configuration.launchArguments + attributes
  }

  private static func environment(fromConfiguration configuration: FBTestRunnerConfiguration, environment: [String: String]) -> [String: String] {
    var mEnvironment = configuration.launchEnvironment
    for (key, value) in environment {
      mEnvironment[key] = value
    }
    return mEnvironment
  }
}
