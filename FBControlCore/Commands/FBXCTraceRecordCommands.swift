/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public final class FBXCTraceRecordCommands: FBiOSTargetCommand, XCTraceRecordCommands {

  public let target: any FBiOSTarget

  public class func commands(with target: any FBiOSTarget) -> Self {
    self.init(target: target)
  }

  required init(target: any FBiOSTarget) {
    self.target = target
  }

  // MARK: - Operations

  public func start(configuration: FBXCTraceRecordConfiguration, logger: any FBControlCoreLogger) async throws -> FBXCTraceRecordOperation {
    let shim = try await FBXCTestShimConfiguration.sharedShimConfiguration()
    return try await FBXCTraceRecordOperation.operation(with: target, configuration: configuration.withShim(shim), logger: logger)
  }
}
