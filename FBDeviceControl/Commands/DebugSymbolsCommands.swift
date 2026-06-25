/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

public protocol DebugSymbolsCommands: AnyObject {

  func listSymbols() async throws -> [String]

  func pullSymbolFile(_ fileName: String, toDestinationPath destinationPath: String) async throws -> String

  func pullAndExtractSymbols(toDestinationDirectory destinationDirectory: String) async throws -> String
}

// MARK: - FBDevice+DebugSymbolsCommands

extension FBDevice: DebugSymbolsCommands {

  public func listSymbols() async throws -> [String] {
    try await bridgeFBFutureArray(debugSymbolsCommands().listSymbols()) as [String]
  }

  public func pullSymbolFile(_ fileName: String, toDestinationPath destinationPath: String) async throws -> String {
    try await bridgeFBFuture(debugSymbolsCommands().pullSymbolFile(fileName, toDestinationPath: destinationPath)) as String
  }

  public func pullAndExtractSymbols(toDestinationDirectory destinationDirectory: String) async throws -> String {
    try await bridgeFBFuture(debugSymbolsCommands().pullAndExtractSymbols(toDestinationDirectory: destinationDirectory)) as String
  }
}
