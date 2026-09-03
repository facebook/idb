/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MARK: - FBDevice+XCTraceRecordCommands

extension FBDevice: XCTraceRecordCommands {

  public func startXctraceRecord(
    configuration: FBXCTraceRecordConfiguration,
    logger: any FBControlCoreLogger
  ) async throws -> FBXCTraceRecordOperation {
    try await xctraceRecord.startXctraceRecord(configuration, logger: logger)
  }
}

// MARK: - FBDevice+InstrumentsCommands

extension FBDevice: InstrumentsCommands {

  public func startInstruments(
    configuration: FBInstrumentsConfiguration,
    logger: any FBControlCoreLogger
  ) async throws -> FBInstrumentsOperation {
    try await FBInstrumentsOperation.operationAsync(target: self, configuration: configuration, logger: logger)
  }
}

// MARK: - FBDevice+AsynciOSTarget

extension FBDevice: AsynciOSTarget {}
