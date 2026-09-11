/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public struct InstrumentsTimings: Sendable {

  public let terminateTimeout: TimeInterval
  public let launchRetryTimeout: TimeInterval
  public let launchErrorTimeout: TimeInterval
  public let operationDuration: TimeInterval

  public static func timings(withTerminateTimeout terminateTimeout: TimeInterval, launchRetryTimeout: TimeInterval, launchErrorTimeout: TimeInterval, operationDuration: TimeInterval) -> InstrumentsTimings {
    InstrumentsTimings(terminateTimeout: terminateTimeout, launchRetryTimeout: launchRetryTimeout, launchErrorTimeout: launchErrorTimeout, operationDuration: operationDuration)
  }

  public init(terminateTimeout: TimeInterval, launchRetryTimeout: TimeInterval, launchErrorTimeout: TimeInterval, operationDuration: TimeInterval) {
    self.terminateTimeout = terminateTimeout
    self.launchRetryTimeout = launchRetryTimeout
    self.launchErrorTimeout = launchErrorTimeout
    self.operationDuration = operationDuration
  }
}

public struct InstrumentsConfiguration: Sendable, CustomStringConvertible {

  public let templateName: String
  public let targetApplication: String
  public let appEnvironment: [String: String]
  public let appArguments: [String]
  public let toolArguments: [String]
  public let timings: InstrumentsTimings

  public static func configuration(withTemplateName templateName: String, targetApplication: String, appEnvironment: [String: String], appArguments: [String], toolArguments: [String], timings: InstrumentsTimings) -> InstrumentsConfiguration {
    InstrumentsConfiguration(templateName: templateName, targetApplication: targetApplication, appEnvironment: appEnvironment, appArguments: appArguments, toolArguments: toolArguments, timings: timings)
  }

  public init(templateName: String, targetApplication: String, appEnvironment: [String: String], appArguments: [String], toolArguments: [String], timings: InstrumentsTimings) {
    self.templateName = templateName
    self.targetApplication = targetApplication
    self.appEnvironment = appEnvironment
    self.appArguments = appArguments
    self.toolArguments = toolArguments
    self.timings = timings
  }

  public var description: String {
    "Instruments \(templateName) | \(targetApplication) | \(CollectionInformation.oneLineDescription(from: appEnvironment)) | \(CollectionInformation.oneLineDescription(from: appArguments)) | \(CollectionInformation.oneLineDescription(from: toolArguments)) | duration \(timings.operationDuration) | terminate timeout \(timings.terminateTimeout) | launch retry timeout \(timings.launchRetryTimeout) | launch error timeout \(timings.launchErrorTimeout)"
  }
}
