/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
@preconcurrency import FBDeviceControl
import Foundation
import GRPCCore
import IDBGRPCSwift

struct ForwardPortMethodHandler {
  let target: CompanionTarget
  let allowedPorts: Set<UInt16>

  private enum Completion: Sendable {
    case inputFinished
    case outputFinished
    case drainTimedOut
  }

  static func parseAllowedPorts(_ value: String?) throws -> Set<UInt16> {
    guard let value, !value.isEmpty else { return [] }
    let ports = try value.split(separator: ",", omittingEmptySubsequences: false).map { part in
      guard let port = UInt16(part.trimmingCharacters(in: .whitespaces)), port > 0 else {
        throw RPCError(code: .invalidArgument, message: "Invalid allowed device port: \(part)")
      }
      return port
    }
    return Set(ports)
  }

  static func openingPort(_ request: Idb_ForwardPortRequest, allowedPorts: Set<UInt16>) throws -> UInt16 {
    guard case let .open(open) = request.event, let port = UInt16(exactly: open.port), port > 0 else {
      throw RPCError(code: .invalidArgument, message: "First message must open a device port in 1...65535")
    }
    if !allowedPorts.contains(port) {
      throw RPCError(code: .permissionDenied, message: "Forwarding device port \(port) is not allowed")
    }
    return port
  }

  func handle(requestStream: RequestStreamReader<Idb_ForwardPortRequest>, responseStream: RPCWriter<Idb_ForwardPortResponse>) async throws {
    try await Self.withAllowedPort(from: requestStream, allowedPorts: allowedPorts) { port in
      guard let device = target as? Device else {
        throw RPCError(code: .unimplemented, message: "Device port forwarding requires a physical iOS device")
      }
      try await device.socketForwarding.withPortConnection(port: port) { socket in
        try await responseStream.send(.with { $0.opened = .init() })
        try await Self.pipe(socket: socket, requests: requestStream) { response in
          try await responseStream.send(response)
        }
      }
    }
  }

  static func withAllowedPort<Result>(
    from requestStream: RequestStreamReader<Idb_ForwardPortRequest>,
    allowedPorts: Set<UInt16>,
    _ connect: (UInt16) async throws -> Result
  ) async throws -> Result {
    let port = try openingPort(try await requestStream.requiredNext(), allowedPorts: allowedPorts)
    return try await connect(port)
  }

  static func pipe<Requests: AsyncSequence & Sendable>(
    socket: SocketStream,
    requests: Requests,
    drainTimeout: Duration = .seconds(4),
    send: @escaping @Sendable (Idb_ForwardPortResponse) async throws -> Void
  ) async throws where Requests.Element == Idb_ForwardPortRequest {
    try await withTaskCancellationHandler {
      try await withThrowingTaskGroup(of: Completion.self) { group in
        defer {
          socket.close()
          group.cancelAll()
        }
        group.addTask {
          for try await request in requests {
            guard case let .data(data) = request.event else {
              throw RPCError(code: .invalidArgument, message: "Expected data after opening device port")
            }
            guard data.count <= SocketStream.chunkSize else {
              throw RPCError(code: .resourceExhausted, message: "Forwarding chunks must not exceed 64 KiB")
            }
            try await socket.write(data)
          }
          try Task.checkCancellation()
          return .inputFinished
        }
        group.addTask {
          while let data = try await socket.read() {
            try await send(.with { $0.data = data })
          }
          return .outputFinished
        }
        if try await group.next() == .inputFinished {
          group.addTask {
            try await Task.sleep(for: drainTimeout)
            return .drainTimedOut
          }
          if try await group.next() == .drainTimedOut {
            throw RPCError(
              code: .deadlineExceeded,
              message: "Device response drain exceeded \(drainTimeout) after request-stream completion"
            )
          }
        }
      }
      try Task.checkCancellation()
    } onCancel: {
      socket.close()
    }
  }
}
