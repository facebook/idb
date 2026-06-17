/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

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

  /// The path of the container on the host filesystem, if it is backed by a
  /// single real directory. `nil` for containers that don't map to one host path.
  var pathOnHostFileSystem: String? { get }

  /// A mapping of identifiers to host filesystem paths, for containers that
  /// expose multiple roots (e.g. per-application or per-group containers).
  /// `nil` for containers that don't expose such a mapping.
  var pathMapping: [String: String]? { get }
}

public extension AsyncFileContainer {

  var pathOnHostFileSystem: String? { nil }

  var pathMapping: [String: String]? { nil }
}
