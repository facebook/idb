/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

@objc public enum FBIDBTestOperationState: UInt {
  case notRunning
  case terminatedNormally
  case terminatedAbnormally
  case running
}

@objc public final class FBIDBTestOperation: NSObject, FBiOSTargetOperation {

  @objc public let completed: FBFuture<NSNull>
  @objc public let logger: FBControlCoreLogger
  @objc public let queue: DispatchQueue
  @objc public let reporter: FBXCTestReporter
  @objc public let reporterConfiguration: FBXCTestReporterConfiguration
  private let configuration: AnyObject

  @objc public var state: FBIDBTestOperationState {
    if completed.error != nil {
      return .terminatedAbnormally
    }
    return completed.hasCompleted ? .terminatedNormally : .running
  }

  @objc public init(configuration: AnyObject, reporterConfiguration: FBXCTestReporterConfiguration, reporter: FBXCTestReporter, logger: FBControlCoreLogger, completed: FBFuture<NSNull>, queue: DispatchQueue) {
    self.configuration = configuration
    self.reporterConfiguration = reporterConfiguration
    self.reporter = reporter
    self.logger = logger
    self.completed = completed
    self.queue = queue
    super.init()
  }

  public override var description: String {
    "Test Run (\(configuration))"
  }
}
