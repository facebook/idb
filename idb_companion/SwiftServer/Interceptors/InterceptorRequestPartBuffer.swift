/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPC
import NIOCore

enum InterceptorRequestPartBufferKey<Request, Response>: UserInfo.Key {
    typealias Value = InterceptorRequestPartBuffer<Request, Response>
}

final class InterceptorRequestPartBuffer<Request, Response> {
    private let eventLoop: EventLoop
    private var hasBeenResolved = false

    private var bufferedParts: [GRPCServerRequestPart<Request>] = []

    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }

    func receive(_ part: GRPCServerRequestPart<Request>, context: ServerInterceptorContext<Request, Response>, resolved: Bool) {
        eventLoop.preconditionInEventLoop()

        guard !hasBeenResolved else {
            context.receive(part)
            return
        }

        guard resolved else {
            bufferedParts.append(part)
            return
        }
        hasBeenResolved = true
        context.receive(part)
        for part in bufferedParts {
            context.receive(part)
        }
    }
}
