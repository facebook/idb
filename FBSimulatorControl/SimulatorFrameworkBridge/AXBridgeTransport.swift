/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorBridgeProtocol
import Foundation

package protocol AXBridgeTransport {
  func send(_ request: AXBridgeRequest) async throws -> Data
  /// As `send`, failing with `AXBridgeError.guestNotAnswering` when the guest has sent nothing back within
  /// `receiveTimeout`.
  func send(_ request: AXBridgeRequest, receiveTimeout: TimeInterval) async throws -> Data
}

extension AXBridgeTransport where Self: Sendable {
  /// Races the round trip against the timeout. A transport that can bound its own wait — and so drop a
  /// connection a late reply would otherwise arrive on — overrides this.
  ///
  /// The round trip runs unstructured, so a `send` that ignores cancellation cannot hold the caller past the
  /// timeout; it is cancelled and left to finish alone.
  package func send(_ request: AXBridgeRequest, receiveTimeout: TimeInterval) async throws -> Data {
    let answer = AsyncEvent<Data>()
    let roundTrip = Task {
      do {
        answer.happen(try await send(request))
      } catch {
        answer.fail(error)
      }
    }
    defer { roundTrip.cancel() }
    do {
      return try await answer.wait(timeout: receiveTimeout, waitingFor: "the axbridge guest to answer")
    } catch is PollTimeoutError {
      throw AXBridgeError.guestNotAnswering(after: receiveTimeout)
    }
  }
}

/// A transport that can hold a connection open for a response streamed in many frames.
package protocol AXBridgeStreamingTransport: AXBridgeTransport {
  func stream(_ request: AXBridgeRequest) async throws -> AsyncThrowingStream<Data, Error>
}
