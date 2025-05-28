/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCAccessibilityElement, XCTCapabilities, XCTScreenshotRequest, XCTSpindumpRequestSpecification, XCTSerializedTransportWrapper, XCTImage, XCElementSnapshot, XCUIElementSnapshotRequestResult;

@protocol XCTMessagingRole_CapabilityExchange
- (void)_XCT_requestElementAtPoint:(struct CGPoint)arg1 reply:(void (^)(XCAccessibilityElement *, NSError *))arg2;
- (void)_XCT_fetchParameterizedAttribute:(NSString *)arg1 forElement:(XCAccessibilityElement *)arg2 parameter:(id)arg3 reply:(void (^)(id, NSError *))arg4;
- (void)_XCT_fetchParameterizedAttributeForElement:(XCAccessibilityElement *)arg1 attributes:(NSNumber *)arg2 parameter:(id)arg3 reply:(void (^)(id, NSError *))arg4;
- (void)_XCT_setAttribute:(NSNumber *)arg1 value:(id)arg2 element:(XCAccessibilityElement *)arg3 reply:(void (^)(_Bool, NSError *))arg4;
- (void)_XCT_fetchAttributes:(NSArray *)arg1 forElement:(XCAccessibilityElement *)arg2 reply:(void (^)(NSDictionary *, NSError *))arg3;
- (void)_XCT_fetchAttributesForElement:(XCAccessibilityElement *)arg1 attributes:(NSArray *)arg2 reply:(void (^)(NSDictionary *, NSError *))arg3;
- (void)_XCT_fetchSnapshotForElement:(XCAccessibilityElement *)arg1 attributes:(NSArray *)arg2 parameters:(NSDictionary *)arg3 reply:(void (^)(XCUIElementSnapshotRequestResult *, NSError *))arg4;
- (void)_XCT_requestSnapshotForElement:(XCAccessibilityElement *)arg1 attributes:(NSArray *)arg2 parameters:(NSDictionary *)arg3 reply:(void (^)(XCElementSnapshot *, NSError *))arg4;
- (void)_XCT_snapshotForElement:(XCAccessibilityElement *)arg1 attributes:(NSArray *)arg2 parameters:(NSDictionary *)arg3 reply:(void (^)(XCElementSnapshot *, NSError *))arg4;
- (void)_XCT_terminateApplicationWithBundleID:(NSString *)arg1 completion:(void (^)(NSError *))arg2;
- (void)_XCT_performAccessibilityAction:(int)arg1 onElement:(XCAccessibilityElement *)arg2 withValue:(id)arg3 reply:(void (^)(NSError *))arg4;
- (void)_XCT_unregisterForAccessibilityNotification:(int)arg1 withRegistrationToken:(NSNumber *)arg2 reply:(void (^)(NSError *))arg3;
- (void)_XCT_registerForAccessibilityNotification:(int)arg1 reply:(void (^)(NSNumber *, NSError *))arg2;
- (void)_XCT_launchApplicationWithBundleID:(NSString *)arg1 arguments:(NSArray *)arg2 environment:(NSDictionary *)arg3 completion:(void (^)(NSError *))arg4;
- (void)_XCT_startMonitoringApplicationWithBundleID:(NSString *)arg1;
- (void)_XCT_requestBackgroundAssertionWithReply:(void (^)(void))arg1;
- (void)_XCT_requestBackgroundAssertionForPID:(int)arg1 reply:(void (^)(_Bool))arg2;
- (void)_XCT_requestScreenshotWithReply:(void (^)(NSData *, NSError *))arg1;
- (void)_XCT_requestScreenshotOfScreenWithID:(unsigned int)arg1 withRect:(struct CGRect)arg2 uti:(NSString *)arg3 compressionQuality:(double)arg4 withReply:(void (^)(NSData *, NSError *))arg5;
- (void)_XCT_requestScreenshot:(XCTScreenshotRequest *)arg1 withReply:(void (^)(XCTImage *, NSError *))arg2;
- (void)_XCT_requestSpindumpWithSpecification:(XCTSpindumpRequestSpecification *)arg1 completion:(void (^)(NSData *, NSError *))arg2;
- (void)_XCT_requestUnsupportedBundleIdentifiersForAutomationSessions:(void (^)(NSSet *, NSError *))arg1;
- (void)_XCT_requestEndpointForTestTargetWithPID:(int)arg1 preferredBackendPath:(NSString *)arg2 reply:(void (^)(NSXPCListenerEndpoint *, NSError *))arg3;
- (void)_XCT_requestSerializedTransportWrapperForIDESessionWithIdentifier:(NSUUID *)arg1 reply:(void (^)(XCTSerializedTransportWrapper *))arg2;
- (void)_XCT_requestSocketForSessionIdentifier:(NSUUID *)arg1 reply:(void (^)(NSFileHandle *))arg2;
- (void)_XCT_exchangeCapabilities:(XCTCapabilities *)arg1 reply:(void (^)(XCTCapabilities *))arg2;
- (void)_XCT_exchangeProtocolVersion:(unsigned long long)arg1 reply:(void (^)(unsigned long long))arg2;
@end

