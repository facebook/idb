/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@protocol DTXAllowedRPC;

@protocol DTXConnectionRemoteReceiveQueueCalls <DTXAllowedRPC>
- (void)_notifyCompressionHint:(unsigned int)arg1 forChannelCode:(unsigned int)arg2;
- (void)_setTracerState:(unsigned int)arg1;
- (void)_channelCanceled:(unsigned int)arg1;
- (void)_notifyOfPublishedCapabilities:(NSDictionary *)arg1;
- (void)_requestChannelWithCode:(unsigned int)arg1 identifier:(NSString *)arg2;
@end

