/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import IDBGRPCSwift

/// A companion connection with one open `repl` stream.
///
/// gRPC Swift 2 scopes both the client and a bidirectional call to a closure, but a REPL
/// session outlives any single method call on it: the stream opened at handshake carries
/// every later `execute`. The connection therefore runs those closures on a task of its own
/// and exposes the stream's two halves as a request continuation and a response iterator.
/// Reads and writes are made sequentially from the session's single task.
final class ReplConnection: @unchecked Sendable {

  typealias Transport = HTTP2ClientTransport.Posix

  /// The service client, for unary and server-streaming calls made beside the `repl` stream.
  let client: Idb_CompanionService.Client<Transport>

  private let grpcClient: GRPCClient<Transport>

  private let requests: AsyncStream<Idb_ReplRequest>.Continuation
  private var responses: AsyncThrowingStream<Idb_ReplResponse, any Error>.Iterator
  private let clientTask: Task<Void, any Error>
  private let callTask: Task<Void, any Error>

  private init(
    grpcClient: GRPCClient<Transport>,
    requests: AsyncStream<Idb_ReplRequest>.Continuation,
    responses: AsyncThrowingStream<Idb_ReplResponse, any Error>.Iterator,
    clientTask: Task<Void, any Error>,
    callTask: Task<Void, any Error>
  ) {
    self.grpcClient = grpcClient
    self.client = Idb_CompanionService.Client(wrapping: grpcClient)
    self.requests = requests
    self.responses = responses
    self.clientTask = clientTask
    self.callTask = callTask
  }

  /// Connects over `transport` and opens the `repl` stream, which stays open until ``close()``.
  static func open(transport: Transport) async throws -> ReplConnection {
    let client = GRPCClient(transport: transport)
    let clientTask = Task {
      try await client.runConnections()
    }

    let (requestStream, requests) = AsyncStream<Idb_ReplRequest>.makeStream()
    let (responseStream, responses) = AsyncThrowingStream<Idb_ReplResponse, any Error>.makeStream()
    let service = Idb_CompanionService.Client(wrapping: client)
    let callTask = Task {
      do {
        try await service.repl(
          request: StreamingClientRequest { writer in
            for await request in requestStream {
              try await writer.write(request)
            }
          }
        ) { response in
          for try await message in response.messages {
            responses.yield(message)
          }
        }
        responses.finish()
      } catch {
        responses.finish(throwing: error)
        throw error
      }
    }

    return ReplConnection(
      grpcClient: client,
      requests: requests,
      responses: responseStream.makeAsyncIterator(),
      clientTask: clientTask,
      callTask: callTask)
  }

  func send(_ request: Idb_ReplRequest) async throws {
    requests.yield(request)
  }

  /// The next response on the `repl` stream, or nil once the companion has closed it.
  func nextResponse() async throws -> Idb_ReplResponse? {
    try await responses.next()
  }

  /// Completes the request half of the `repl` stream, waits for the call to end, and closes
  /// the connection.
  func close() async {
    requests.finish()
    _ = try? await callTask.value
    grpcClient.beginGracefulShutdown()
    _ = try? await clientTask.value
  }
}
