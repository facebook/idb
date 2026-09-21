/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <CoreSimulator/FoundationXPCProtocolProxyable-Protocol.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SimScreenAdapter <FoundationXPCProtocolProxyable>
- (void)enumerateScreensWithCompletionQueue:(dispatch_queue_t)queue
                         completionHandler:(void (^)(NSArray *))completionHandler;
@end

NS_ASSUME_NONNULL_END
