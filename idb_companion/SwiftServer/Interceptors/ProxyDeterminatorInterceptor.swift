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

  override func receive(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>) {
    switch part {
    case let .metadata(headers):

      if ProcessInfo.processInfo.environment["IDB_HANDLE_ALL_GRPC_SWIFT"] == "YES" {
        context.userInfo[CallSwiftMethodNatively.self] = true
      } else {
        context.userInfo[CallSwiftMethodNatively.self] = swiftMethodsHeaderContainsCurrentMethod(headers: headers, context: context)
      }

    default:
      break
    }
    context.receive(part)
  }

  private func swiftMethodsHeaderContainsCurrentMethod(headers: HPACKHeaders, context: ServerInterceptorContext<Request, Response>) -> Bool {
    let swiftMethodsValue = headers["idb-swift-methods"]

    let methodName = extractMethodName(path: context.path)
    let swiftMethods = swiftMethodsValue
      .reduce("", +)
      .split(separator: ",")

    return swiftMethods.contains(methodName)
  }

  private func extractMethodName(path: String) -> Substring {
    path
      .suffix(from: path.lastIndex(of: "/")!)
      .dropFirst()
  }


}
