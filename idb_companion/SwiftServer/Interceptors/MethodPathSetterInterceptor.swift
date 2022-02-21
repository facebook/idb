/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPC

enum MethodPathKey: UserInfo.Key {
   typealias Value = String
}

final class MethodPathSetterInterceptor<Request, Response>: ServerInterceptor<Request, Response> {

  override func receive(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>) {
    context.userInfo[MethodPathKey.self] = context.path
    context.receive(part)
  }

}
