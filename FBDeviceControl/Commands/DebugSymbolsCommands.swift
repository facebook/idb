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
    try await debugSymbolsCommands.listSymbols()
  }

  public func pullSymbolFile(_ fileName: String, toDestinationPath destinationPath: String) async throws -> String {
    try await debugSymbolsCommands.pullSymbolFile(fileName, toDestinationPath: destinationPath)
  }

  public func pullAndExtractSymbols(toDestinationDirectory destinationDirectory: String) async throws -> String {
    try await debugSymbolsCommands.pullAndExtractSymbols(toDestinationDirectory: destinationDirectory)
  }
}
