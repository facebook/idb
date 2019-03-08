/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class NSString;

@protocol XCTestManager_TestsInterface
- (void)_XCT_applicationWithBundleID:(NSString *)arg1 didUpdatePID:(int)arg2 andState:(unsigned long long)arg3;
// iOS 10.x specific
- (void)_XCT_receivedAccessibilityNotification:(int)arg1 withPayload:(NSData *)arg2;
@end

