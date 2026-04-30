/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBInstrumentsCommandsProtocol: NSObjectProtocol, FBiOSTargetCommand {

  @objc(startInstruments:logger:)
  func startInstruments(_ configuration: FBInstrumentsConfiguration, logger: FBControlCoreLogger) -> FBFuture<FBInstrumentsOperation>
}

public extension FBInstrumentsCommandsProtocol {

  func startInstrumentsAsync(_ configuration: FBInstrumentsConfiguration, logger: any FBControlCoreLogger) async throws -> FBInstrumentsOperation {
    try await bridgeFBFuture(self.startInstruments(configuration, logger: logger))
  }
}

// FBInstrumentsCommands conforms via ObjC category in FBInstrumentsCommands.m
