/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation
import SimulatorFrameworkBridgeProtocol

#if canImport(SimulatorFrameworkBridgeRuntime)
@_implementationOnly import SimulatorFrameworkBridgeRuntime
#endif

public struct BridgeRPCReply {
  public let data: Data
  public let exitCode: Int32
  public let shutdown: Bool
}

public enum BridgeRPC {
  public static func process(_ data: Data, execute: (BridgeCommand) -> BridgeResult = BridgeServices.execute) -> BridgeRPCReply {
    guard (try? BridgeFrame.header(forSize: data.count)) != nil else { return failure(id: nil, message: "invalid request size") }
    let request: BridgeRequest
    do {
      request = try BridgeRequest.decode(data)
    } catch {
      return failure(id: BridgeRequest.identity(of: data), message: String(describing: error))
    }
    let result = execute(request.command)
    do {
      let bytes = try BridgeResponse(request: request, result: result).encoded()
      _ = try BridgeFrame.header(forSize: bytes.count)
      return BridgeRPCReply(data: bytes, exitCode: result.exitCode, shutdown: request.command == .shutdown && result.exitCode == 0)
    } catch {
      return failure(id: request.id, message: "response serialization failed or exceeded the frame limit")
    }
  }

  private static func failure(id: String?, message: String) -> BridgeRPCReply {
    let response = BridgeResponse(id: id, result: BridgeResult(exitCode: 1, error: message))
    let encoded = try? response.encoded()
    let data = encoded.flatMap { $0.count <= BridgeFrame.maximumSize ? $0 : nil } ?? Data(#"{"version":1,"result":{"exitCode":1,"values":[]}}"#.utf8)
    return BridgeRPCReply(data: data, exitCode: 1, shutdown: false)
  }

  public static func handle(_ data: Data, execute: (BridgeCommand) -> BridgeResult = BridgeServices.execute) -> BridgeSocketResponse {
    let reply = process(data, execute: execute)
    return .frame(data: reply.data, shutdown: reply.shutdown)
  }

  static func run(arguments: [String]) -> Int32? {
    guard arguments.count >= 2 else { return nil }
    switch arguments[1] {
    case "rpc":
      guard arguments.count == 3 else { return 1 }
      let reply = process(Data(arguments[2].utf8))
      let written = reply.data.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, stdout) == $0.count }
      guard written, fputc(10, stdout) != EOF, fflush(stdout) == 0 else { return 1 }
      return reply.exitCode
    case "serve":
      guard arguments.count >= 3, !arguments[2].isEmpty else { return 1 }
      let options = Array(arguments.dropFirst(3))
      return BridgeServer.serve(
        socketPath: arguments[2],
        idleTimeoutSeconds: BridgeServeOptions.idleTimeout(arguments: options, fallback: BridgeServer.defaultIdleTimeoutSeconds),
        initialClientTimeoutSeconds: BridgeServeOptions.startupTimeout(arguments: options),
        exitOnDisconnect: BridgeServeOptions.exitOnDisconnect(arguments: options),
        // Bind the accessibility frameworks before the first client so the first read does not pay
        // for it inside the client's timeout.
        prepareRuntime: { FBAXClientProvider.prepare() },
        handleRequest: { handle($0) }
      )
    default:
      return nil
    }
  }
}
