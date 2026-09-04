/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

public enum FBIDBTestOperationState: UInt {
  case notRunning
  case terminatedNormally
  case terminatedAbnormally
  case running
}

public final class FBIDBTestOperation: CustomStringConvertible {

  /// The configuration the run was started from. A logic test and an app-hosted test are
  /// configured by unrelated types, and only one of the two is ever in play.
  public enum Configuration: CustomStringConvertible {
    case logic(FBLogicTestConfiguration)
    case appHosted(FBTestLaunchConfiguration)

    public var description: String {
      switch self {
      case let .logic(configuration):
        return String(describing: configuration)
      case let .appHosted(configuration):
        return String(describing: configuration)
      }
    }
  }

  public let completed: FBFuture<NSNull>
  public let logger: FBControlCoreLogger
  public let queue: DispatchQueue
  public let reporter: FBXCTestReporter
  public let reporterConfiguration: FBXCTestReporterConfiguration
  private let configuration: Configuration

  public var state: FBIDBTestOperationState {
    if completed.error != nil {
      return .terminatedAbnormally
    }
    return completed.hasCompleted ? .terminatedNormally : .running
  }

  public init(configuration: Configuration, reporterConfiguration: FBXCTestReporterConfiguration, reporter: FBXCTestReporter, logger: FBControlCoreLogger, completed: FBFuture<NSNull>, queue: DispatchQueue) {
    self.configuration = configuration
    self.reporterConfiguration = reporterConfiguration
    self.reporter = reporter
    self.logger = logger
    self.completed = completed
    self.queue = queue
  }

  public func awaitCompletion() async throws {
    try await bridgeFBFutureVoid(self.completed)
  }

  public var description: String {
    "Test Run (\(configuration))"
  }
}
