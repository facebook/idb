/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

@class FBSimulatorControl;
@class FBSimulatorPool;
@class FBSimulatorSession;
@protocol FBInteraction;

/**
 FBSimulatorControl Assertion Helpers.
 */
@interface XCTestCase (FBSimulatorControlAssertions)

#pragma mark Interactions

- (void)assertInteractionSuccessful:(id<FBInteraction>)interaction;
- (void)assertInteractionFailed:(id<FBInteraction>)interaction;

#pragma mark Sessions

- (void)assertShutdownSimulatorAndTerminateSession:(FBSimulatorSession *)session;

#pragma mark Strings

- (void)assertNeedle:(NSString *)needle inHaystack:(NSString *)haystack;

@end

/**
 Assertion Helpers for FBSimulatorControl Notifications.
 */
@interface FBSimulatorControlNotificationAssertions : NSObject

+ (instancetype)withTestCase:(XCTestCase *)testCase pool:(FBSimulatorPool *)pool;

- (NSNotification *)consumeNotification:(NSString *)notificationName;
- (NSNotification *)consumeNotification:(NSString *)notificationName timeout:(NSTimeInterval)timeout;
- (void)consumeAllNotifications;
- (void)noNotificationsToConsume;

@end

