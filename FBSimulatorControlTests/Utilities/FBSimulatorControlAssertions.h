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
@class FBSimulatorSession;
@protocol FBInteraction;

/**
 Higher-level Assertions.
 */
@interface FBSimulatorControlAssertions : NSObject

+ (instancetype)withTestCase:(XCTestCase *)testCase;

#pragma mark Notifications

- (NSNotification *)consumeNotification:(NSString *)notificationName;
- (NSNotification *)consumeNotification:(NSString *)notificationName timeout:(NSTimeInterval)timeout;
- (void)consumeAllNotifications;
- (void)noNotificationsToConsume;

#pragma mark Interactions

- (void)interactionSuccessful:(id<FBInteraction>)interaction;
- (void)interactionFailed:(id<FBInteraction>)interaction;

#pragma mark Sessions

- (void)shutdownSimulatorAndTerminateSession:(FBSimulatorSession *)session;

#pragma mark Strings

- (void)needle:(NSString *)needle inHaystack:(NSString *)haystack;

@end
