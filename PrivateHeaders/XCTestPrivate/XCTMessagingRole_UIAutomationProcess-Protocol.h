/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCAccessibilityElement, XCTCapabilities, XCTElementQuery, XCTElementQueryResults, XCTSerializedTransportWrapper2;

@protocol XCTMessagingRole_UIAutomationProcess <NSObject>
- (void)listenForRemoteConnectionViaSerializedTransportWrapper:(XCTSerializedTransportWrapper2 *)arg1 completion:(void (^)(void))arg2;
- (void)notifyWhenAnimationsAreIdle:(void (^)(NSError *))arg1;
- (void)notifyWhenMainRunLoopIsIdle:(void (^)(NSError *))arg1;
- (void)attributesForElement:(XCAccessibilityElement *)arg1 attributes:(NSArray *)arg2 reply:(void (^)(NSDictionary *, NSError *))arg3;
- (void)fetchMatchesForQuery:(XCTElementQuery *)arg1 reply:(void (^)(XCTElementQueryResults *, NSError *))arg2;
- (void)exchangeCapabilities:(XCTCapabilities *)arg1 reply:(void (^)(XCTCapabilities *))arg2;
- (void)requestHostAppExecutableNameWithReply:(void (^)(NSString *))arg1;
@end

