/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBDeviceDebugSymbolsCommandsProtocol: NSObjectProtocol {

  @objc func listSymbols() -> FBFuture<NSArray>

  @objc(pullSymbolFile:toDestinationPath:)
  func pullSymbolFile(_ fileName: String, toDestinationPath destinationPath: String) -> FBFuture<NSString>

  @objc(pullAndExtractSymbolsToDestinationDirectory:)
  func pullAndExtractSymbols(toDestinationDirectory destinationDirectory: String) -> FBFuture<NSString>
}

// FBDevice and FBDeviceDebugSymbolsCommands conform at runtime via ObjC.
// Do not add Swift extension conformance here - ObjC classes use
// forwardingTargetForSelector: and commandsWithTarget: which cannot
// be verified by the Swift compiler at compile time.
