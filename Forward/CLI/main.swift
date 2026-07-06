/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import Darwin
import Foundation
import NIOCore
import NIOPosix
import NIOSSL

@main
struct IdbForward {
  static func main() async {
    let allArguments = Array(CommandLine.arguments.dropFirst())

    // Pull recognized flags out of the argument list; everything else is
    // forwarded to the companion. `--idb-companion-binary` overrides the default
    // system-installed companion CompanionDiscovery launches (mirrors idb-repl's
    // flag). `--companion <host:port>` connects directly to a TCP companion,
    // bypassing discovery entirely. `--tls`/`--tls-ca-cert`/`--tls-insecure`
    // configure TLS for that TCP connection.
    var udid: String?
    var companionBinary: String?
    var explicitCompanion: String?
    var useTLS = false
    var tlsCACertPath: String?
    var tlsInsecure = false
    var remainingArguments: [String] = []
    var iterator = allArguments.makeIterator()
    while let argument = iterator.next() {
      switch argument {
      case "--udid": udid = iterator.next()
      case "--idb-companion-binary": companionBinary = iterator.next()
      case "--companion": explicitCompanion = iterator.next()
      case "--tls": useTLS = true
      case "--tls-ca-cert": tlsCACertPath = iterator.next()
      case "--tls-insecure": tlsInsecure = true
      default: remainingArguments.append(argument)
      }
    }

    logStderr("Remaining arguments: \(remainingArguments)")

    // Any TLS-related flag enables TLS; nil means a plaintext connection.
    let tls: TLSClientOptions? =
      (useTLS || tlsCACertPath != nil || tlsInsecure)
      ? TLSClientOptions(caCertPath: tlsCACertPath, insecure: tlsInsecure) : nil

    // Resolve the companion address. With `--companion host:port` we connect to an
    // explicit (typically remote) TCP companion and skip CompanionDiscovery
    // entirely. Otherwise we discover a companion, starting one if needed (it
    // exits after 5 minutes idle); with no udid we use the single running
    // companion or start one for the only available simulator.
    let address: CompanionAddress
    if let explicitCompanion {
      guard let parsed = parseTCPAddress(explicitCompanion) else {
        logStderr("Error: --companion expects host:port, e.g. 127.0.0.1:10882 (got '\(explicitCompanion)')")
        exit(1)
      }
      address = parsed
      logStderr("Companion: explicit \(addressDescription(parsed))")
    } else {
      let idleShutdownTime = 5 * 60
      let manager = CompanionManager(version: .v2, companionPath: companionBinary)
      let companion: CompanionInfo
      do {
        if let udid {
          companion = try await manager.companionInfo(forUDID: udid, idleShutdownTime: idleShutdownTime)
        } else {
          companion = try await manager.defaultCompanion(idleShutdownTime: idleShutdownTime)
        }
      } catch {
        logStderr("Error: \(error)")
        exit(1)
      }
      logCompanion(companion)
      address = companion.address
    }

    // Forward the remaining arguments to the companion as a `cli` JSON-RPC
    // request: the companion runs them through idb2's ArgumentParser and returns
    // the command's stdout and exit code, which we relay as our own.
    switch address {
    case let .domainSocket(path):
      if tls != nil {
        logStderr("Note: TLS options are ignored for a Unix domain socket companion")
      }
      let response: Data
      do {
        response = try sendCLICommand(remainingArguments, toSocketPath: path)
      } catch {
        logStderr("Error: \(error)")
        exit(1)
      }
      emit(response)
    case let .tcp(host, port):
      let response: Data
      do {
        response = try await sendCLICommandTCP(remainingArguments, host: host, port: port, tls: tls)
      } catch {
        logStderr("Error: \(error)")
        exit(1)
      }
      emit(response)
    }
  }

  /// Parses the companion's JSON-RPC response: writes the command's stdout to our
  /// stdout and exits with its exit code, or reports an error response.
  private static func emit(_ data: Data) -> Never {
    var json = data
    while json.last == 0x0A || json.last == 0x0D {
      json.removeLast()
    }
    guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
      logStderr("Error: companion returned an invalid response")
      exit(1)
    }
    if let result = object["result"] as? [String: Any] {
      let output = result["stdout"] as? String ?? ""
      let exitCode = (result["exitCode"] as? NSNumber)?.int32Value ?? 0
      FileHandle.standardOutput.write(Data(output.utf8))
      exit(exitCode)
    }
    if let errorObject = object["error"] as? [String: Any] {
      logStderr("Error: \(errorObject["message"] as? String ?? "\(errorObject)")")
      exit(1)
    }
    logStderr("Error: companion response had neither result nor error")
    exit(1)
  }

  /// Writes a diagnostic line to stderr, keeping stdout for the forwarded
  /// command's own output.
  private static func logStderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }

  private static func addressDescription(_ address: CompanionAddress) -> String {
    switch address {
    case let .tcp(host, port): return "tcp \(host):\(port)"
    case let .domainSocket(path): return "unix \(path)"
    }
  }

  private static func logCompanion(_ companion: CompanionInfo) {
    logStderr("Companion: udid=\(companion.udid) isLocal=\(companion.isLocal) pid=\(companion.pid.map(String.init) ?? "none") address=\(addressDescription(companion.address))")
  }

  enum ForwardError: Error, CustomStringConvertible {
    case encodeFailed
    case connectFailed(path: String, code: Int32)
    case writeFailed

    var description: String {
      switch self {
      case .encodeFailed:
        return "Failed to encode the JSON-RPC request"
      case let .connectFailed(path, code):
        return "Failed to connect to the companion socket at \(path) (errno \(code))"
      case .writeFailed:
        return "Failed to write the command to the companion socket"
      }
    }
  }

  /// Encodes `arguments` as a `cli` JSON-RPC request, writes it (newline framed)
  /// to the companion listening on `path`, then reads the response to EOF and
  /// returns it.
  private static func sendCLICommand(_ arguments: [String], toSocketPath path: String) throws -> Data {
    let request: [String: Any] = [
      "jsonrpc": "2.0",
      "method": "cli",
      "params": arguments,
      "id": 1,
    ]
    guard var data = try? JSONSerialization.data(withJSONObject: request) else {
      throw ForwardError.encodeFailed
    }
    data.append(0x0A) // newline frames the message for the server

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw ForwardError.connectFailed(path: path, code: errno)
    }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard path.utf8.count < capacity else {
      throw ForwardError.connectFailed(path: path, code: ENAMETOOLONG)
    }
    withUnsafeMutablePointer(to: &addr.sun_path) { rawPointer in
      rawPointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
        _ = strncpy(destination, path, capacity - 1)
      }
    }
    let length = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &addr) { addrPointer in
      addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.connect(fd, sockaddrPointer, length)
      }
    }
    guard connected == 0 else {
      throw ForwardError.connectFailed(path: path, code: errno)
    }

    try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let base = raw.baseAddress else { return }
      var written = 0
      while written < raw.count {
        let n = Darwin.write(fd, base + written, raw.count - written)
        guard n > 0 else {
          throw ForwardError.writeFailed
        }
        written += n
      }
    }

    // Read the response to EOF: the companion writes one JSON-RPC response line
    // and then closes the connection.
    var response = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
      let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
      if n <= 0 {
        break
      }
      response.append(contentsOf: chunk[0..<n])
    }
    return response
  }

  // MARK: - TCP transport

  /// TLS settings for a TCP companion connection.
  private struct TLSClientOptions {
    /// PEM of the CA/certificate to trust instead of the system roots (for a
    /// private or self-signed server cert). Ignored when `insecure` is true.
    var caCertPath: String?
    /// Skip certificate and hostname verification entirely. Insecure; for
    /// development against a server the client cannot otherwise trust.
    var insecure: Bool
  }

  /// Parses a `host:port` (or `[ipv6]:port`) string into a `.tcp` address, or nil
  /// if malformed. Splits on the last colon so a bracketed IPv6 literal works.
  private static func parseTCPAddress(_ value: String) -> CompanionAddress? {
    guard let colon = value.lastIndex(of: ":") else { return nil }
    var host = String(value[value.startIndex..<colon])
    let portString = String(value[value.index(after: colon)...])
    guard let port = Int(portString), (1...65535).contains(port) else { return nil }
    if host.hasPrefix("[") && host.hasSuffix("]") {
      host = String(host.dropFirst().dropLast())
    }
    guard !host.isEmpty else { return nil }
    return .tcp(host: host, port: port)
  }

  private static func isIPLiteral(_ host: String) -> Bool {
    var v4 = in_addr()
    if inet_pton(AF_INET, host, &v4) == 1 { return true }
    var v6 = in6_addr()
    if inet_pton(AF_INET6, host, &v6) == 1 { return true }
    return false
  }

  private static func makeClientSSLContext(_ tls: TLSClientOptions) throws -> NIOSSLContext {
    var configuration = TLSConfiguration.makeClientConfiguration()
    if tls.insecure {
      configuration.certificateVerification = .none
    } else if let caCertPath = tls.caCertPath {
      configuration.trustRoots = .file(caCertPath)
    }
    return try NIOSSLContext(configuration: configuration)
  }

  /// Encodes `arguments` as a `cli` JSON-RPC request, opens a TCP connection to
  /// `host:port` (TLS when `tls` is set), writes it (newline framed), then reads
  /// the response to EOF and returns it. The TCP analogue of `sendCLICommand`,
  /// implemented over SwiftNIO so TLS is available.
  private static func sendCLICommandTCP(
    _ arguments: [String],
    host: String,
    port: Int,
    tls: TLSClientOptions?
  ) async throws -> Data {
    let request: [String: Any] = [
      "jsonrpc": "2.0",
      "method": "cli",
      "params": arguments,
      "id": 1,
    ]
    guard var data = try? JSONSerialization.data(withJSONObject: request) else {
      throw ForwardError.encodeFailed
    }
    data.append(0x0A) // newline frames the message for the server

    let sslContext = try tls.map { try makeClientSSLContext($0) }

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    do {
      // The accumulator completes this promise with the full response on EOF (the
      // companion writes one line then closes) or with an error on failure.
      let responsePromise = group.next().makePromise(of: Data.self)
      let bootstrap = ClientBootstrap(group: group)
        .channelInitializer { channel in
          var handlers: [ChannelHandler] = []
          if let sslContext {
            // NIOSSL rejects an IP literal as an SNI server name, so pass nil for
            // one (cert IP-SAN verification still applies); otherwise the hostname
            // drives both SNI and hostname verification.
            let serverHostname = isIPLiteral(host) ? nil : host
            do {
              handlers.append(try NIOSSLClientHandler(context: sslContext, serverHostname: serverHostname))
            } catch {
              return channel.eventLoop.makeFailedFuture(error)
            }
          }
          handlers.append(ResponseAccumulator(promise: responsePromise))
          return channel.pipeline.addHandlers(handlers)
        }

      let channel = try await bootstrap.connect(host: host, port: port).get()
      var buffer = channel.allocator.buffer(capacity: data.count)
      buffer.writeBytes(data)
      try await channel.writeAndFlush(buffer).get()
      let response = try await responsePromise.futureResult.get()
      try? await group.shutdownGracefully()
      return response
    } catch {
      try? await group.shutdownGracefully()
      throw error
    }
  }
}

/// Collects all bytes received on a connection and completes `promise` with them
/// when the peer closes (EOF). The companion writes one JSON-RPC response line and
/// then closes, so EOF marks the end of the response — matching the read-to-EOF
/// behavior of the Unix-domain-socket client. All callbacks run on the channel's
/// event loop, so the mutable state needs no extra synchronization.
private final class ResponseAccumulator: ChannelInboundHandler {
  typealias InboundIn = ByteBuffer

  private let promise: EventLoopPromise<Data>
  private var accumulated = Data()
  private var finished = false

  init(promise: EventLoopPromise<Data>) {
    self.promise = promise
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    var buffer = unwrapInboundIn(data)
    if let bytes = buffer.readBytes(length: buffer.readableBytes) {
      accumulated.append(contentsOf: bytes)
    }
  }

  func channelInactive(context: ChannelHandlerContext) {
    finish(.success(accumulated))
    context.fireChannelInactive()
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    finish(.failure(error))
    context.close(promise: nil)
  }

  private func finish(_ result: Result<Data, Error>) {
    guard !finished else { return }
    finished = true
    promise.completeWith(result)
  }
}
