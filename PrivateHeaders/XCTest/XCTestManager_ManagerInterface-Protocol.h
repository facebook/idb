/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class NSUUID;

@protocol XCTestManager_ManagerInterface
- (void)_XCT_loadAccessibilityWithTimeout:(double)arg1 reply:(void (^)(_Bool, NSError *))arg2;
- (void)_XCT_setAXTimeout:(double)arg1 reply:(void (^)(int))arg2;
- (void)_XCT_requestScreenshotWithReply:(void (^)(NSData *, NSError *))arg1;
- (void)_XCT_sendString:(NSString *)arg1 maximumFrequency:(unsigned long long)arg2 completion:(void (^)(NSError *))arg3;
- (void)_XCT_updateDeviceOrientation:(long long)arg1 completion:(void (^)(NSError *))arg2;
- (void)_XCT_performDeviceEvent:(XCDeviceEvent *)arg1 completion:(void (^)(NSError *))arg2;
- (void)_XCT_synthesizeEvent:(XCSynthesizedEventRecord *)arg1 completion:(void (^)(NSError *))arg2;
- (void)_XCT_requestElementAtPoint:(struct CGPoint)arg1 reply:(void (^)(XCAccessibilityElement *, NSError *))arg2;
- (void)_XCT_fetchParameterizedAttributeForElement:(XCAccessibilityElement *)arg1 attributes:(NSNumber *)arg2 parameter:(id)arg3 reply:(void (^)(id, NSError *))arg4;
- (void)_XCT_fetchAttributesForElement:(XCAccessibilityElement *)arg1 attributes:(NSArray *)arg2 reply:(void (^)(NSDictionary *, NSError *))arg3;
- (void)_XCT_snapshotForElement:(XCAccessibilityElement *)arg1 attributes:(NSArray *)arg2 parameters:(NSDictionary *)arg3 reply:(void (^)(XCElementSnapshot *, NSError *))arg4;
- (void)_XCT_terminateApplicationWithBundleID:(NSString *)arg1 completion:(void (^)(NSError *))arg2;
- (void)_XCT_performAccessibilityAction:(int)arg1 onElement:(XCAccessibilityElement *)arg2 withValue:(id)arg3 reply:(void (^)(NSError *))arg4;
- (void)_XCT_unregisterForAccessibilityNotification:(int)arg1 withRegistrationToken:(NSNumber *)arg2 reply:(void (^)(NSError *))arg3;
- (void)_XCT_registerForAccessibilityNotification:(int)arg1 reply:(void (^)(NSNumber *, NSError *))arg2;
- (void)_XCT_launchApplicationWithBundleID:(NSString *)arg1 arguments:(NSArray *)arg2 environment:(NSDictionary *)arg3 completion:(void (^)(NSError *))arg4;
- (void)_XCT_startMonitoringApplicationWithBundleID:(NSString *)arg1;
- (void)_XCT_requestBackgroundAssertionForPID:(int)arg1 reply:(void (^)(_Bool))arg2;
- (void)_XCT_requestBackgroundAssertionWithReply:(void (^)(void))arg1;
- (void)_XCT_requestSocketForSessionIdentifier:(NSUUID *)arg1 reply:(void (^)(NSFileHandle *))arg2;
- (void)_XCT_exchangeProtocolVersion:(unsigned long long)arg1 reply:(void (^)(unsigned long long))arg2;
@end

