/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBXCTraceRecordCommandsProtocol`.
public protocol AsyncXCTraceRecordCommands: AnyObject {

  func startXctraceRecord(
    configuration: FBXCTraceRecordConfiguration,
    logger: any FBControlCoreLogger
  ) async throws -> FBXCTraceRecordOperation
}

/// Default bridge implementation against the legacy
/// `FBXCTraceRecordCommandsProtocol`.
extension AsyncXCTraceRecordCommands where Self: FBXCTraceRecordCommandsProtocol {

  public func startXctraceRecord(
    configuration: FBXCTraceRecordConfiguration,
    logger: any FBControlCoreLogger
  ) async throws -> FBXCTraceRecordOperation {
    try await bridgeFBFuture(self.startXctraceRecord(configuration, logger: logger))
  }
}
