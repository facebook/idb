/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import NIO

private enum MethodStartKey: UserInfo.Key {
  typealias Value = Date
}

final class LoggingInterceptor<Request, Response>: ServerInterceptor<Request, Response> {

  private let logger: FBIDBLogger
  private let reporter: FBEventReporter

  init(logger: FBIDBLogger, reporter: FBEventReporter) {
    self.logger = logger
    self.reporter = reporter
  }

  // MARK: Request start + incoming frames

  override func receive(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>) {
    guard let methodInfo = context.userInfo[MethodInfoKey.self] else {
      assertionFailure("MethodInfoKey is empty, you have incorrect interceptor order")
      super.receive(part, context: context)
      return
    }

    switch part {
    case .metadata:
      saveStartDate(in: context)
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

  private func saveStartDate(in context: ServerInterceptorContext<Request, Response>) {
    context.userInfo[MethodStartKey.self] = Date()
  }

  private func reportMethodStart(methodName: String, in context: ServerInterceptorContext<Request, Response>) {
    logger.info().log("Start of \(methodName)")
    let subject = FBEventReporterSubject(forStartedCall: methodName, arguments: [], reportNativeSwiftMethodCall: true)
    reporter.report(subject)
  }

  // MARK: Request end + outgoing frames

  override func send(_ part: GRPCServerResponsePart<Response>, promise: EventLoopPromise<Void>?, context: ServerInterceptorContext<Request, Response>) {
    guard let methodInfo = context.userInfo[MethodInfoKey.self] else {
      assertionFailure("MethodInfoKey is empty, you have incorrect interceptor order")
      super.send(part, promise: promise, context: context)
      return
    }

    switch part {
    case let .end(status, _):
      reportMethodEnd(methodName: methodInfo.name, status: status, context: context)

    default:
      break
    }

    super.send(part, promise: promise, context: context)
  }

  private func reportMethodEnd(methodName: String, status: GRPCStatus, context: ServerInterceptorContext<Request, Response>) {
    let duration = getMethodDuration(context: context)

    let subject: FBEventReporterSubject
    if status.isOk {
      logger.debug().log("Success of \(methodName)")
      subject = FBEventReporterSubject(forSuccessfulCall: methodName, duration: duration, size: nil, arguments: [], reportNativeSwiftMethodCall: true)
    } else {
      logger.info().log("Failure of \(methodName), \(status)")
      subject = FBEventReporterSubject(forFailingCall: methodName, duration: duration, message: status.message ?? "Unknown error with code \(status.code)", size: nil, arguments: [], reportNativeSwiftMethodCall: true)
    }

    reporter.report(subject)
  }

  private func getMethodDuration(context: ServerInterceptorContext<Request, Response>) -> TimeInterval {
    guard let methodStartDate = context.userInfo[MethodStartKey.self] else {
      assertionFailure("\(MethodStartKey.self) is not configured on request start")
      return 0
    }
    return Date().timeIntervalSince(methodStartDate)
  }
}
