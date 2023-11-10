/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class NSString;

@protocol XCTMessagingRole_ProtectedResourceAuthorization
- (void)_XCT_resetAuthorizationStatusForBundleIdentifier:(NSString *)arg1 resourceIdentifier:(NSString *)arg2 reply:(void (^)(_Bool, NSError *))arg3;
@end

