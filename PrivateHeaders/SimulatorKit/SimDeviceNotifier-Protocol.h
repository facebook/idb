/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

@class OS_dispatch_queue;

@protocol SimDeviceNotifier
- (unsigned long long)registerNotificationHandlerOnQueue:(OS_dispatch_queue *)arg1 handler:(void (^)(NSDictionary *))arg2;
- (BOOL)unregisterNotificationHandler:(unsigned long long)arg1 error:(id *)arg2;
@end
