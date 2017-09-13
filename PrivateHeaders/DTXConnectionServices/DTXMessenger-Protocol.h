/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

