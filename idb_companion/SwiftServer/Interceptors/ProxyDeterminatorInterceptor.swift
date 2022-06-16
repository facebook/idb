/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPC
import NIOHPACK

enum CallSwiftMethodNatively: UserInfo.Key {
  typealias Value = Bool
}

final class ProxyDeterminatorInterceptor<Request, Response>: ServerInterceptor<Request, Response> {

  private enum Key: String {
    case idbSwiftMethods = "idb-swift-methods"
  }

  private let killswitch: IDBKillswitch

  init(killswitch: IDBKillswitch) {
    self.killswitch = killswitch
  }

  override func receive(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>) {
    switch part {
    case let .metadata(headers):
      if setProxyFlagFromEnvironmentIfFound(part, context: context) {
        return
      }

      guard let methodName = context.userInfo[MethodInfoKey.self]?.name else {
        assertionFailure("MethodInfoKey is empty, you have incorrect interceptor order")
        context.userInfo[CallSwiftMethodNatively.self] = false
        context.receive(part)
        return
      }

      if setProxyFlagFromGRPCHeadersIfFound(part, context: context, headers: headers, methodName: methodName) {
        return
      }

      let buffer = InterceptorRequestPartBuffer<Request, Response>(eventLoop: context.eventLoop)
      context.userInfo[InterceptorRequestPartBufferKey<Request, Response>.self] = buffer

      setProxyFlagFromKillswitchConfig(part, context: context, methodName: methodName, suspendingRequestsTo: buffer)

    default:
      guard let buffer = context.userInfo[InterceptorRequestPartBufferKey<Request, Response>.self] else {
        // If we use determination from headers/env, buffer is not created and we just passthrough requests as always
        context.receive(part)
        return
      }
      buffer.receive(part, context: context, resolved: false)
    }
  }

  private func setProxyFlagFromEnvironmentIfFound(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>) -> Bool {
    if ProcessInfo.processInfo.environment["IDB_HANDLE_ALL_GRPC_SWIFT"] == "YES" {
      context.userInfo[CallSwiftMethodNatively.self] = true
      context.receive(part)
      return true
    }
    return false
  }

  private func setProxyFlagFromGRPCHeadersIfFound(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>, headers: HPACKHeaders, methodName: String) -> Bool {
    if headers.contains(name: Key.idbSwiftMethods.rawValue) {
      context.userInfo[CallSwiftMethodNatively.self] = swiftMethodsHeaderContainsCurrentMethod(headers: headers, methodName: methodName)
      context.receive(part)
      return true
    }
    return false
  }

  private func setProxyFlagFromKillswitchConfig(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>, methodName: String, suspendingRequestsTo buffer: InterceptorRequestPartBuffer<Request, Response>) {
    checkIsKillswitched(methodName: methodName) { isKillswitched in
      context.eventLoop.execute {
        context.userInfo[CallSwiftMethodNatively.self] = !isKillswitched
        buffer.receive(part, context: context, resolved: true)
      }
    }
  }

  private func checkIsKillswitched(methodName: String, handler: @Sendable @escaping (_ isKillswitched: Bool) -> Void) {
    Task {
      let isKillswitched = await killswitch.disabled(.grpcMethod(methodName))
      handler(isKillswitched)
    }
  }

  private func swiftMethodsHeaderContainsCurrentMethod(headers: HPACKHeaders, methodName: String) -> Bool {
    let swiftMethodsValue = headers[Key.idbSwiftMethods.rawValue]

    let swiftMethods = swiftMethodsValue
      .reduce("", +)
      .split(separator: ",")

    return swiftMethods.contains(Substring(methodName))
  }

}
