/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import GRPC
import NIO

final class LoggingInterceptor<Request, Response>: ServerInterceptor<Request, Response> {

  private let logger: FBIDBLogger
  private let reporter: FBEventReporter

  init(logger: FBIDBLogger, reporter: FBEventReporter) {
    self.logger = logger
    self.reporter = reporter
  }

  override func receive(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>) {
    switch part {
    case .metadata:
      let willBeCalledNatively = context.userInfo[CallSwiftMethodNatively.self] == true
      if !willBeCalledNatively {
        logger.info().log("Start of \(context.path), proxying to cpp server")
      } else {
        logger.info().log("Start of \(context.path), call natively")
      }

    case .message where context.type == .clientStreaming || context.type == .bidirectionalStreaming:
      logger.debug().log("Receive frame of \(context.path)")

    case .end where context.type == .clientStreaming || context.type == .bidirectionalStreaming:
      logger.debug().log("Close client stream of \(context.path)")

    default:
      break
    }

    super.receive(part, context: context)
  }

  override func send(_ part: GRPCServerResponsePart<Response>, promise: EventLoopPromise<Void>?, context: ServerInterceptorContext<Request, Response>) {
    switch part {
    case .message where context.type == .serverStreaming || context.type == .bidirectionalStreaming:
      logger.debug().log("Send frame of \(context.path)")

    case let .end(status, _):
      if status.isOk {
        logger.debug().log("Success of \(context.path)")
      } else {
        logger.info().log("Failure of \(context.path), \(status)")
      }

    default:
      break
    }

    super.send(part, promise: promise, context: context)
  }

}
