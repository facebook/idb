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
@protocol FBInteraction;

@interface FBSimulatorControlAssertions : NSObject

+ (instancetype)withTestCase:(XCTestCase *)testCase;

#pragma mark Notifications

- (void)notificationRecieved:(NSNotification *)notification;
- (void)consumeNotification:(NSString *)notificationName;
- (void)noNotificationsToConsume;

#pragma mark Interactions

- (void)interactionSuccessful:(id<FBInteraction>)interaction;

@end
