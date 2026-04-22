/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import Foundation
import GRPC
import IDBCompanionUtilities
import IDBGRPCSwift

enum MethodInfoKey: UserInfo.Key {
  typealias Value = GRPCMethodInfo
}

struct GRPCMethodInfo {
  let name: String
  let path: String
  let callType: GRPCCallType
}

final class MethodInfoSetterInterceptor<Request, Response>: ServerInterceptor<Request, Response> {

  @Atomic var methodDescriptors: [String: GRPCMethodDescriptor] = Idb_CompanionServiceServerMetadata
    .serviceDescriptor
    .methods
    .reduce(into: [:]) { $0[$1.path] = $1 }

  override func receive(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>) {
    switch part {
    case .metadata:
      let methodInfo: GRPCMethodInfo
      if let methodDescriptor = methodDescriptors[context.path] {
        methodInfo = GRPCMethodInfo(
          name: methodDescriptor.name,
          path: methodDescriptor.path,
          callType: methodDescriptor.type)
      } else {
        assertionFailure("Method not found in descriptors list. If this is client and companion version mismatch, ignore that error")
        // context.callType is not reported correctly in ServerInterceptorContext and always return .bidirectionalStreaming
        methodInfo = GRPCMethodInfo(
          name: String(extractMethodName(path: context.path)),
          path: context.path,
          callType: context.type)
      }
      context.userInfo[MethodInfoKey.self] = methodInfo

    default:
      break
    }

    super.receive(part, context: context)
  }

  private func extractMethodName(path: String) -> Substring {
    path
      .suffix(from: path.lastIndex(of: "/")!)
      .dropFirst()
  }
}
