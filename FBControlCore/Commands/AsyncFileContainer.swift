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

/// Adapter wrapping a `tail` result (a teardown trigger future) in
/// `FBiOSTargetOperation` shape so the default bridge has something to return.
private final class FileContainerTailOperation: NSObject, FBiOSTargetOperation {

  private let teardown: FBFuture<NSNull>

  init(teardown: FBFuture<NSNull>) {
    self.teardown = teardown
    super.init()
  }

  var completed: FBFuture<NSNull> {
    teardown
  }
}

/// Default bridge implementation against the legacy `FBFileContainerProtocol`.
extension AsyncFileContainer where Self: FBFileContainerProtocol {

  public func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    try await bridgeFBFutureVoid(self.copy(fromHost: sourcePath, toContainer: destinationPath))
  }

  public func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    let result = try await bridgeFBFuture(self.copy(fromContainer: sourcePath, toHost: destinationPath))
    return result as String
  }

  public func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> any FBiOSTargetOperation {
    // The legacy API returns FBFuture<FBFuture<NSNull>>: the outer future
    // resolves once tailing has *started*, the inner future resolves once
    // tailing has finished. Treat the inner future as the operation handle.
    let inner = try await bridgeFBFuture(self.tail(path, to: consumer))
    return FileContainerTailOperation(teardown: inner)
  }

  public func createDirectory(_ directoryPath: String) async throws {
    try await bridgeFBFutureVoid(self.createDirectory(directoryPath))
  }

  public func move(from sourcePath: String, to destinationPath: String) async throws {
    try await bridgeFBFutureVoid(self.move(from: sourcePath, to: destinationPath))
  }

  public func remove(_ path: String) async throws {
    try await bridgeFBFutureVoid(self.remove(path))
  }

  public func contents(ofDirectory path: String) async throws -> [String] {
    try await bridgeFBFutureArray(self.contents(ofDirectory: path))
  }
}

/// Adapter that wraps an `FBFileContainerProtocol` instance and exposes the
/// `AsyncFileContainer` async API. Concrete `FBFileContainerProtocol`
/// implementations are scattered across Objective-C internals, so call sites
/// wrap a value through this adapter to access the async API directly.
public final class AsyncFileContainerAdapter: NSObject, FBFileContainerProtocol, AsyncFileContainer {

  private let underlying: any FBFileContainerProtocol

  public init(_ underlying: any FBFileContainerProtocol) {
    self.underlying = underlying
    super.init()
  }

  public func copy(fromHost sourcePath: String, toContainer destinationPath: String) -> FBFuture<NSNull> {
    underlying.copy(fromHost: sourcePath, toContainer: destinationPath)
  }

  public func copy(fromContainer sourcePath: String, toHost destinationPath: String) -> FBFuture<NSString> {
    underlying.copy(fromContainer: sourcePath, toHost: destinationPath)
  }

  public func tail(_ path: String, to consumer: any FBDataConsumer) -> FBFuture<FBFuture<NSNull>> {
    underlying.tail(path, to: consumer)
  }

  public func createDirectory(_ directoryPath: String) -> FBFuture<NSNull> {
    underlying.createDirectory(directoryPath)
  }

  public func move(from sourcePath: String, to destinationPath: String) -> FBFuture<NSNull> {
    underlying.move(from: sourcePath, to: destinationPath)
  }

  public func remove(_ path: String) -> FBFuture<NSNull> {
    underlying.remove(path)
  }

  public func contents(ofDirectory path: String) -> FBFuture<NSArray> {
    underlying.contents(ofDirectory: path)
  }
}
