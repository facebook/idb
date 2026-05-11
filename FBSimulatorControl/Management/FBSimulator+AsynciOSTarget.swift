/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MARK: - FBSimulator+AsyncXCTraceRecordCommands

extension FBSimulator: AsyncXCTraceRecordCommands {

  public func startXctraceRecord(
    configuration: FBXCTraceRecordConfiguration,
    logger: any FBControlCoreLogger
  ) async throws -> FBXCTraceRecordOperation {
    try await bridgeFBFuture(xctraceRecordCommands().startXctraceRecord(configuration, logger: logger))
  }
}

// MARK: - FBSimulator+AsyncInstrumentsCommands

extension FBSimulator: AsyncInstrumentsCommands {

  public func startInstruments(
    configuration: FBInstrumentsConfiguration,
    logger: any FBControlCoreLogger
  ) async throws -> FBInstrumentsOperation {
    try await bridgeFBFuture(instrumentsCommands().startInstruments(configuration, logger: logger))
  }
}

// MARK: - FBSimulator+AsynciOSTarget

extension FBSimulator: AsynciOSTarget {

  public func compare(_ target: any AsynciOSTarget) -> ComparisonResult {
    guard let other = target as? any FBiOSTarget else {
      return .orderedSame
    }
    return FBiOSTargetComparison(self, other)
  }
}
