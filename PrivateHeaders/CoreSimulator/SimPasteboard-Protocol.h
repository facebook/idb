/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
