/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBInstrumentsCommandsProtocol`.
public protocol AsyncInstrumentsCommands: AnyObject {

  func startInstruments(
    configuration: FBInstrumentsConfiguration,
    logger: any FBControlCoreLogger
  ) async throws -> FBInstrumentsOperation
}

/// Default bridge implementation against the legacy
/// `FBInstrumentsCommandsProtocol`.
extension AsyncInstrumentsCommands where Self: FBInstrumentsCommandsProtocol {

  public func startInstruments(
    configuration: FBInstrumentsConfiguration,
    logger: any FBControlCoreLogger
  ) async throws -> FBInstrumentsOperation {
    try await bridgeFBFuture(self.startInstruments(configuration, logger: logger))
  }
}
