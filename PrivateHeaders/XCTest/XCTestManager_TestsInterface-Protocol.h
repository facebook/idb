/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

@class NSString;

@protocol XCTestManager_TestsInterface
- (void)_XCT_applicationWithBundleID:(NSString *)arg1 didUpdatePID:(int)arg2 andState:(unsigned long long)arg3;
// iOS 10.x specific
- (void)_XCT_receivedAccessibilityNotification:(int)arg1 withPayload:(NSData *)arg2;
@end

