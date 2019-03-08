/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSObject.h"

@class DTXMessage;

@protocol DTXMessenger <NSObject>
- (void)sendMessageSync:(DTXMessage *)arg1 replyHandler:(void (^)(DTXMessage *))arg2;
- (BOOL)sendMessageAsync:(DTXMessage *)arg1 replyHandler:(void (^)(DTXMessage *))arg2;
- (void)sendMessage:(DTXMessage *)arg1 replyHandler:(void (^)(DTXMessage *))arg2;
- (void)sendControlSync:(DTXMessage *)arg1 replyHandler:(void (^)(DTXMessage *))arg2;
- (void)sendControlAsync:(DTXMessage *)arg1 replyHandler:(void (^)(DTXMessage *))arg2;
- (void)cancel;
- (void)registerDisconnectHandler:(void (^)(void))arg1;
- (void)setDispatchTarget:(id <DTXAllowedRPC>)arg1;
- (void)setMessageHandler:(void (^)(DTXMessage *))arg1;
@end

