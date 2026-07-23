/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol XCTraceRecordCommands: AnyObject {

  func startXctraceRecord(
    configuration: FBXCTraceRecordConfiguration,
    logger: any FBControlCoreLogger
  ) async throws -> FBXCTraceRecordOperation
}
