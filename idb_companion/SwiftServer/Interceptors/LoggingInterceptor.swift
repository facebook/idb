/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC

/// Logs gRPC transport-level lifecycle for each call: the request start and, for
/// streaming calls, each received frame and the client-stream close.
///
/// Call *completion* (success/failure) is intentionally not logged or reported
/// here. A server interceptor's `send(.end)` is not invoked when a client cancels
/// or drops the connection mid-call, so completion observed at this layer is
/// unreliable and would silently miss such calls. `CompanionTelemetry` wraps every
/// handler in a `do`/`catch` and reports completion — and the success/failure
/// `FBEventReporter` event — reliably on every termination path, so it is the
/// single source for that.
final class LoggingInterceptor<Request, Response>: ServerInterceptor<Request, Response> {

  private let logger: FBIDBLogger

  init(logger: FBIDBLogger) {
    self.logger = logger
  }

  override func receive(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>) {
    guard let methodInfo = context.userInfo[MethodInfoKey.self] else {
      assertionFailure("MethodInfoKey is empty, you have incorrect interceptor order")
      super.receive(part, context: context)
      return
    }

    switch part {
    case .metadata:
      logger.info().log("Start of \(methodInfo.name)")

    case .message where methodInfo.callType == .clientStreaming || methodInfo.callType == .bidirectionalStreaming:
      logger.debug().log("Receive frame of \(methodInfo.name)")

    case .end where methodInfo.callType == .clientStreaming || methodInfo.callType == .bidirectionalStreaming:
      logger.debug().log("Close client stream of \(methodInfo.name)")

    default:
      break
    }

    super.receive(part, context: context)
  }
}
