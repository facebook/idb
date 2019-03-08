/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDeviceNotifier-Protocol.h>

@class NSArray, NSObject;
@protocol OS_dispatch_queue;

@protocol SimPasteboard <SimDeviceNotifier>
@property (atomic, copy, readonly) NSArray *items;
@property (atomic, readonly) unsigned long long changeCount;
- (void)setPasteboardAsyncWithItems:(NSArray *)arg1 completionQueue:(NSObject<OS_dispatch_queue> *)arg2 completionHandler:(void (^)(unsigned long long, NSError *))arg3;
- (unsigned long long)setPasteboardWithItems:(NSArray *)arg1 error:(id *)arg2;
@end
