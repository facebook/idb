/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPC
import NIO

/// Reports each gRPC call's start and end to an `IdleShutdownMonitor` so the
/// companion can shut down after a period with no requests. A call starts at its
/// request metadata and ends when the server sends the final status — the same
/// lifecycle boundaries `LoggingInterceptor` observes.
final class IdleShutdownInterceptor<Request, Response>: ServerInterceptor<Request, Response> {

  private let monitor: IdleShutdownMonitor

  init(monitor: IdleShutdownMonitor) {
    self.monitor = monitor
  }

  override func receive(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>) {
    if case .metadata = part {
      monitor.requestStarted()
    }
    super.receive(part, context: context)
  }

  override func send(_ part: GRPCServerResponsePart<Response>, promise: EventLoopPromise<Void>?, context: ServerInterceptorContext<Request, Response>) {
    if case .end = part {
      monitor.requestEnded()
    }
    super.send(part, promise: promise, context: context)
  }
}
