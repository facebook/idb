/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPCCore

enum StreamReadError<Element>: Error {
  case nextElementNotProduced

  var rpcError: RPCError {
    switch self {
    case .nextElementNotProduced:
      return RPCError(code: .failedPrecondition, message: "Expected next element of type \(Element.self)")
    }
  }
}

/// The one reader of a method's request stream.
///
/// `RPCAsyncSequence` may only be iterated once: a second iterator is a programmer error that
/// the transport does not recover from. The iterator is therefore made once, where the stream
/// arrives, and handlers are handed a reader instead of the stream -- so a handler that reads in
/// several places resumes the one read rather than starting a second.
///
/// Being a reference is what lets that read position reach a child task; an iterator is a
/// value, and `inout` cannot cross a task boundary. Reads are handed between tasks, never
/// overlapped: a handler either reads on its own task or awaits the child it lent the reader to.
final class RequestStreamReader<Element: Sendable>: AsyncSequence, AsyncIteratorProtocol, @unchecked Sendable {

  private var iterator: RPCAsyncSequence<Element, any Error>.AsyncIterator

  init(_ stream: RPCAsyncSequence<Element, any Error>) {
    self.iterator = stream.makeAsyncIterator()
  }

  func makeAsyncIterator() -> RequestStreamReader<Element> {
    self
  }

  func next() async throws -> Element? {
    try await iterator.next()
  }

  /// The next element, throwing `failedPrecondition` instead of returning nil when the stream has ended.
  func requiredNext() async throws -> Element {
    guard let next = try await next() else {
      throw StreamReadError<Element>.nextElementNotProduced.rpcError
    }
    return next
  }
}
