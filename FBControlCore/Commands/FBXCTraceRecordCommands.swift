/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBXCTraceRecordCommandsProtocol: NSObjectProtocol, FBiOSTargetCommand {

  @objc(startXctraceRecord:logger:)
  func startXctraceRecord(_ configuration: FBXCTraceRecordConfiguration, logger: FBControlCoreLogger) -> FBFuture<FBXCTraceRecordOperation>
}

public extension FBXCTraceRecordCommandsProtocol {

  func startXctraceRecordAsync(_ configuration: FBXCTraceRecordConfiguration, logger: any FBControlCoreLogger) async throws -> FBXCTraceRecordOperation {
    try await bridgeFBFuture(self.startXctraceRecord(configuration, logger: logger))
  }
}

@objc(FBXCTraceRecordCommands)
public class FBXCTraceRecordCommands: NSObject, FBXCTraceRecordCommandsProtocol {

  // MARK: Properties

  @objc public let target: any FBiOSTarget

  // MARK: Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(target: target)
  }

  required init(target: any FBiOSTarget) {
    self.target = target
    super.init()
  }

  // MARK: FBXCTraceRecordCommandsProtocol

  public func startXctraceRecord(_ configuration: FBXCTraceRecordConfiguration, logger: any FBControlCoreLogger) -> FBFuture<FBXCTraceRecordOperation> {
    let result = FBXCTestShimConfiguration.sharedShimConfiguration(with: logger)
      .onQueue(
        target.workQueue,
        fmap: { shim in
          let op = FBXCTraceRecordOperation.operation(with: self.target, configuration: configuration.withShim(shim), logger: logger)
          return unsafeBitCast(op, to: FBFuture<AnyObject>.self)
        })
    return unsafeBitCast(result, to: FBFuture<FBXCTraceRecordOperation>.self)
  }
}
