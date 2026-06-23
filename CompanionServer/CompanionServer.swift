/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import Darwin
import Foundation
@_implementationOnly import NIOCore
@_implementationOnly import NIOPosix

/// Writes a diagnostic line to stderr. The server keeps stdout free for a host's
/// own protocol (e.g. idb2's `companion` subcommand prints the socket path on
/// stdout as a readiness handshake), so all server logging goes to stderr.
func companionServerLog(_ message: String) {
  try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
}

/// A companion server that listens on a Unix domain socket and accepts incoming
/// JSON-RPC connections.
///
/// On `start()` it binds the conventional socket path for its `udid` under the
/// selected `CompanionVersion` (default `.v2`) and records itself in that
/// version's `CompanionDiscovery` registry, so a discoverer (e.g.
/// `CompanionManager(version: .v2)`) finds it. Incoming connections are framed as
/// newline-delimited JSON-RPC; for now each received request is just handed to
/// `onRequest`, which by default prints it.
///
/// Only Unix domain sockets are supported today; TCP can be layered on later.
public final class CompanionServer {
  /// Invoked for every JSON-RPC request received on any connection.
  public typealias RequestHandler = @Sendable (JSONRPCRequest) -> Void

  private let udid: String
  private let paths: CompanionPaths
  private let registry: CompanionRegistry
  private let onRequest: RequestHandler
  private let group: MultiThreadedEventLoopGroup
  private var channel: Channel?

  /// - Parameters:
  ///   - udid: the target the server fronts. Determines the conventional socket
  ///     path (`<udid>_companion.sock`) and the registry key.
  ///   - version: which companion generation to register under. Determines the
  ///     base directory for the socket and registry (see `CompanionPaths`).
  ///     Defaults to `.v2`.
  ///   - registry: the registry to record this server in. Defaults to one rooted
  ///     at `version`'s state file; pass an explicit registry to override it
  ///     (e.g. a test fixture with an isolated state file).
  ///   - onRequest: invoked for each received JSON-RPC request. Defaults to
  ///     printing the request.
  public init(
    udid: String,
    version: CompanionVersion = .v2,
    registry: CompanionRegistry? = nil,
    onRequest: RequestHandler? = nil
  ) {
    let paths = CompanionPaths(version: version)
    self.udid = udid
    self.paths = paths
    self.registry = registry ?? CompanionRegistry(stateFilePath: paths.stateFile)
    self.onRequest = onRequest ?? { request in companionServerLog("CompanionServer received \(request)") }
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  /// Binds the Unix domain socket, starts accepting connections, and records the
  /// server in the registry. Returns the `CompanionInfo` that was registered.
  @discardableResult
  public func start() async throws -> CompanionInfo {
    let socketPath = paths.companionSocketPath(forUDID: udid)
    try prepareSocketPath(socketPath)

    let onRequest = self.onRequest
    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .childChannelInitializer { channel in
        channel.pipeline.addHandlers([
          ByteToMessageHandler(NewlineFrameDecoder()),
          JSONRPCConnectionHandler(onRequest: onRequest),
        ])
      }

    let channel = try await bootstrap.bind(unixDomainSocketPath: socketPath).get()
    self.channel = channel

    let info = CompanionInfo(
      udid: udid,
      isLocal: true,
      pid: ProcessInfo.processInfo.processIdentifier,
      address: .domainSocket(path: socketPath))
    try registry.add(info)

    companionServerLog("CompanionServer listening on \(socketPath) for udid \(udid)")
    return info
  }

  /// Suspends until the server's listening channel is closed.
  public func waitUntilClosed() async throws {
    guard let channel else {
      throw CompanionServerError.notStarted
    }
    try await channel.closeFuture.get()
  }

  /// Stops accepting connections, deregisters from the registry, removes the
  /// socket file, and shuts down the event loop group.
  public func close() async throws {
    if let channel {
      try? await channel.close().get()
      self.channel = nil
    }
    _ = try? registry.remove(udid: udid)
    unlink(paths.companionSocketPath(forUDID: udid))
    try await shutdownGroup()
  }

  // MARK: - Helpers

  /// Ensures the base directory exists and clears a stale socket file, mirroring
  /// the companion's careful cleanup: only an existing *socket* is unlinked, so a
  /// real file at the path is never clobbered.
  private func prepareSocketPath(_ path: String) throws {
    try paths.ensureBaseDirectory()
    var info = stat()
    guard stat(path, &info) == 0 else {
      return // nothing there (or unreadable); bind will surface any real error
    }
    guard (info.st_mode & S_IFMT) == S_IFSOCK else {
      throw CompanionServerError.socketPathOccupied(path: path)
    }
    unlink(path)
  }

  private func shutdownGroup() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      group.shutdownGracefully { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }
}

/// Errors raised while starting or running a `CompanionServer`.
public enum CompanionServerError: Error, CustomStringConvertible {
  /// A non-socket file already exists where the server wants to bind.
  case socketPathOccupied(path: String)
  /// An operation requiring a running server was called before `start()`.
  case notStarted

  public var description: String {
    switch self {
    case let .socketPathOccupied(path):
      return "A non-socket file already exists at the companion socket path: \(path)"
    case .notStarted:
      return "The companion server has not been started"
    }
  }
}
