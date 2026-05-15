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

// MARK: - FBDevice+FBDeviceDebugSymbolsCommandsProtocol

extension FBDevice: FBDeviceDebugSymbolsCommandsProtocol {

  @objc public func listSymbols() -> FBFuture<NSArray> {
    do {
      return try debugSymbolsCommands().listSymbols()
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func pullSymbolFile(_ fileName: String, toDestinationPath destinationPath: String) -> FBFuture<NSString> {
    do {
      return try debugSymbolsCommands().pullSymbolFile(fileName, toDestinationPath: destinationPath)
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func pullAndExtractSymbols(toDestinationDirectory destinationDirectory: String) -> FBFuture<NSString> {
    do {
      return try debugSymbolsCommands().pullAndExtractSymbols(toDestinationDirectory: destinationDirectory)
    } catch {
      return FBFuture(error: error)
    }
  }
}
