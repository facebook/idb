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
    guard let methodInfo = context.userInfo[MethodInfoKey.self] else {
      assertionFailure("MethodInfoKey is empty, you have incorrect interceptor order")
      super.receive(part, context: context)
      return
    }

    switch part {
    case .metadata:
      reportMethodStart(methodName: methodInfo.name, in: context)

    case .message where methodInfo.callType == .clientStreaming || methodInfo.callType == .bidirectionalStreaming:
      logger.debug().log("Receive frame of \(methodInfo.name)")

    case .end where methodInfo.callType == .clientStreaming || methodInfo.callType == .bidirectionalStreaming:
      logger.debug().log("Close client stream of \(methodInfo.name)")

    default:
      break
    }

    super.receive(part, context: context)
  }

  private func reportMethodStart(methodName: String, in context: ServerInterceptorContext<Request, Response>) {
    let willBeCalledNatively = context.userInfo[CallSwiftMethodNatively.self] == true
    if !willBeCalledNatively {
      logger.info().log("Start of \(methodName), proxying to cpp server")
    } else {
      logger.info().log("Start of \(methodName), handling natively")
    }
  }

  override func send(_ part: GRPCServerResponsePart<Response>, promise: EventLoopPromise<Void>?, context: ServerInterceptorContext<Request, Response>) {
    guard let methodInfo = context.userInfo[MethodInfoKey.self] else {
      assertionFailure("MethodInfoKey is empty, you have incorrect interceptor order")
      super.send(part, promise: promise, context: context)
      return
    }

    switch part {
    case .message where methodInfo.callType == .serverStreaming || methodInfo.callType == .bidirectionalStreaming:
      logger.debug().log("Send frame of \(methodInfo.name)")

    case let .end(status, _):
      reportMethodEnd(methodName: methodInfo.name, status: status, context: context)

    default:
      break
    }

    super.send(part, promise: promise, context: context)
  }

  private func reportMethodEnd(methodName: String, status: GRPCStatus, context: ServerInterceptorContext<Request, Response>) {
    if status.isOk {
      logger.debug().log("Success of \(methodName)")
    } else {
      logger.info().log("Failure of \(methodName), \(status)")
    }
  }

}
