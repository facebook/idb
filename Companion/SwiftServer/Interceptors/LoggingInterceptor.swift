/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import CompanionUtilities
import GRPC

/// Logs a one-line summary when a streaming call's client stream closes.
///
/// Call *start* is intentionally not logged here: `CompanionTelemetry` wraps
/// every handler and already logs `<method> called with` at info, so a
/// `Start of` line would duplicate it. Per-frame logging is likewise avoided:
/// a single `hid` stream can carry dozens of frames, so frames are counted
/// and summarized on close instead.
///
/// Call *completion* (success/failure) is intentionally not logged or reported
/// here. A server interceptor's `send(.end)` is not invoked when a client cancels
/// or drops the connection mid-call, so completion observed at this layer is
/// unreliable and would silently miss such calls. `CompanionTelemetry` wraps every
/// handler in a `do`/`catch` and reports completion — and the success/failure
/// `FBEventReporter` event — reliably on every termination path, so it is the
/// single source for that.
///
/// Interceptor instances are created per call by `CompanionServiceInterceptors`,
/// so the frame counter below needs no synchronization.
final class LoggingInterceptor<Request, Response>: ServerInterceptor<Request, Response>, @unchecked Sendable {

  private let logger: FBIDBLogger
  private var frameCount = 0

  init(logger: FBIDBLogger) {
    self.logger = logger
  }

  override func receive(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>) {
    guard let methodInfo = context.userInfo[MethodInfoKey.self] else {
      assertionFailure("MethodInfoKey is empty, you have incorrect interceptor order")
      super.receive(part, context: context)
      return
    }
    let isStreamingCall =
      methodInfo.callType == .clientStreaming || methodInfo.callType == .bidirectionalStreaming

    switch part {
    case .message where isStreamingCall:
      frameCount += 1

    case .end where isStreamingCall:
      logger.debug().log("Closed client stream of \(methodInfo.name) after \(frameCount) frames")

    default:
      break
    }

    super.receive(part, context: context)
  }
}
