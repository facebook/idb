/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBFileContainerProtocol`.
public protocol AsyncFileContainer: AnyObject {

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String

  /// Begins tailing `path` into `consumer` and returns an operation handle.
  /// Awaiting the returned handle waits for tailing to complete; cancelling stops it.
  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> any FBiOSTargetOperation

  func createDirectory(_ directoryPath: String) async throws

  func move(from sourcePath: String, to destinationPath: String) async throws

  func remove(_ path: String) async throws

  func contents(ofDirectory path: String) async throws -> [String]
}
