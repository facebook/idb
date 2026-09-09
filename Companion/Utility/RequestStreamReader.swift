/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPC

enum StreamReadError<Element>: Error, GRPCStatusTransformable {
  case nextElementNotProduced

  func makeGRPCStatus() -> GRPCStatus {
    switch self {
    case .nextElementNotProduced:
      return GRPCStatus(code: .failedPrecondition, message: "Expected next element of type \(Element.self)")
    }
  }
}

/// The one reader of a method's request stream.
///
/// `GRPCAsyncRequestStream` is unicast: asking it for a second iterator is a `fatalError`
/// inside NIO ("allows only a single AsyncIterator to be created") that kills the companion
/// outright, with no `catch` to turn it into a `GRPCStatus` and nothing in the log to say so.
/// The iterator is therefore made once, where the stream arrives, and handlers are handed a
/// reader instead of the stream -- so a handler that reads in several places resumes the one
/// read rather than starting a second.
///
/// Being a reference is what lets that read position reach a child task; an iterator is a
/// value, and `inout` cannot cross a task boundary. Reads are handed between tasks, never
/// overlapped: a handler either reads on its own task or awaits the child it lent the reader to.
final class RequestStreamReader<Element: Sendable>: AsyncSequence, AsyncIteratorProtocol, @unchecked Sendable {

  private var iterator: GRPCAsyncRequestStream<Element>.Iterator

  init(_ stream: GRPCAsyncRequestStream<Element>) {
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
      throw StreamReadError<Element>.nextElementNotProduced
    }
    return next
  }
}
