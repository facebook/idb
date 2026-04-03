/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBInstrumentsTimings)
public final class FBInstrumentsTimings: NSObject {

  @objc public let terminateTimeout: TimeInterval
  @objc public let launchRetryTimeout: TimeInterval
  @objc public let launchErrorTimeout: TimeInterval
  @objc public let operationDuration: TimeInterval

  @objc(timingsWithTerminateTimeout:launchRetryTimeout:launchErrorTimeout:operationDuration:)
  public class func timings(withTerminateTimeout terminateTimeout: TimeInterval, launchRetryTimeout: TimeInterval, launchErrorTimeout: TimeInterval, operationDuration: TimeInterval) -> FBInstrumentsTimings {
    return FBInstrumentsTimings(terminateTimeout: terminateTimeout, launchRetryTimeout: launchRetryTimeout, launchErrorTimeout: launchErrorTimeout, operationDuration: operationDuration)
  }

  @objc
  public init(terminateTimeout: TimeInterval, launchRetryTimeout: TimeInterval, launchErrorTimeout: TimeInterval, operationDuration: TimeInterval) {
    self.terminateTimeout = terminateTimeout
    self.launchRetryTimeout = launchRetryTimeout
    self.launchErrorTimeout = launchErrorTimeout
    self.operationDuration = operationDuration
    super.init()
  }
}

@objc(FBInstrumentsConfiguration)
public final class FBInstrumentsConfiguration: NSObject, NSCopying {

  @objc public let templateName: String
  @objc public let targetApplication: String
  @objc public let appEnvironment: [String: String]
  @objc public let appArguments: [String]
  @objc public let toolArguments: [String]
  @objc public let timings: FBInstrumentsTimings

  @objc(configurationWithTemplateName:targetApplication:appEnvironment:appArguments:toolArguments:timings:)
  public class func configuration(withTemplateName templateName: String, targetApplication: String, appEnvironment: [String: String], appArguments: [String], toolArguments: [String], timings: FBInstrumentsTimings) -> FBInstrumentsConfiguration {
    return FBInstrumentsConfiguration(templateName: templateName, targetApplication: targetApplication, appEnvironment: appEnvironment, appArguments: appArguments, toolArguments: toolArguments, timings: timings)
  }

  @objc
  public init(templateName: String, targetApplication: String, appEnvironment: [String: String], appArguments: [String], toolArguments: [String], timings: FBInstrumentsTimings) {
    self.templateName = templateName
    self.targetApplication = targetApplication
    self.appEnvironment = appEnvironment
    self.appArguments = appArguments
    self.toolArguments = toolArguments
    self.timings = timings
    super.init()
  }

  public override var description: String {
    return "Instruments \(templateName) | \(targetApplication) | \(FBCollectionInformation.oneLineDescription(from: appEnvironment)) | \(FBCollectionInformation.oneLineDescription(from: appArguments)) | \(FBCollectionInformation.oneLineDescription(from: toolArguments)) | duration \(timings.operationDuration) | terminate timeout \(timings.terminateTimeout) | launch retry timeout \(timings.launchRetryTimeout) | launch error timeout \(timings.launchErrorTimeout)"
  }

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }
}
