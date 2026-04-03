/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc public final class FBManagedTestRunStrategy: NSObject {

  @objc public static func runToCompletion(withTarget target: FBiOSTarget & FBXCTestExtendedCommands, configuration: FBTestLaunchConfiguration, codesign: FBCodesignProvider?, workingDirectory: String, reporter: FBXCTestReporter, logger: FBControlCoreLogger) -> FBFuture<NSNull> {
    do {
      try XCTestBootstrapFrameworkLoader.allDependentFrameworks.loadPrivateFrameworks(target.logger)
    } catch {
      return unsafeBitCast(XCTestBootstrapError.describe(error.localizedDescription).failFuture(), to: FBFuture<NSNull>.self)
    }

    let applicationLaunchConfiguration = configuration.applicationLaunchConfiguration

    // Use ObjC runtime to call prepareConfigurationWithTarget: (not directly visible to Swift in mixed module)
    let prepareSelector = NSSelectorFromString("prepareConfigurationWithTarget:testLaunchConfiguration:workingDirectory:codesign:")
    let prepareMethod = (FBTestRunnerConfiguration.self as AnyObject).method(for: prepareSelector)!
    typealias PrepareFunction = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, NSString, FBCodesignProvider?) -> AnyObject
    let prepareCall = unsafeBitCast(prepareMethod, to: PrepareFunction.self)
    let prepareFuture = unsafeDowncast(
      prepareCall(FBTestRunnerConfiguration.self as AnyObject, prepareSelector, target, configuration, workingDirectory as NSString, codesign),
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

            // Use ObjC runtime to call connectAndRunUntilCompletionWithContext:
            let connectSelector = NSSelectorFromString("connectAndRunUntilCompletionWithContext:target:reporter:logger:")
            let connectMethod = (FBTestManagerAPIMediator.self as AnyObject).method(for: connectSelector)!
            typealias ConnectFunction = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject, AnyObject) -> AnyObject
            let connectCall = unsafeBitCast(connectMethod, to: ConnectFunction.self)
            return unsafeDowncast(
              connectCall(FBTestManagerAPIMediator.self as AnyObject, connectSelector, context, target, reporter as AnyObject, logger as AnyObject),
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
