/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlAssertions.h"

#import <FBSimulatorControl/FBInteraction.h>
#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionLifecycle.h>

@interface FBSimulatorControlAssertions ()

@property (nonatomic, strong) NSMutableArray *notificationsRecieved;
@property (nonatomic, weak) XCTestCase *testCase;

@end

@implementation FBSimulatorControlAssertions

+ (instancetype)withTestCase:(XCTestCase *)testCase
{
  FBSimulatorControlAssertions *assertions = [self new];
  assertions.testCase = testCase;
  return assertions;
}

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _notificationsRecieved = [NSMutableArray array];
  [self installNotificationObservers];
  return self;
}

- (void)installNotificationObservers
{
  NSArray *notificationNames = @[
    FBSimulatorSessionDidStartNotification,
    FBSimulatorSessionDidEndNotification,
    FBSimulatorSessionSimulatorProcessDidLaunchNotification,
    FBSimulatorSessionSimulatorProcessDidTerminateNotification,
    FBSimulatorSessionApplicationProcessDidLaunchNotification,
    FBSimulatorSessionApplicationProcessDidTerminateNotification,
    FBSimulatorSessionAgentProcessDidLaunchNotification,
    FBSimulatorSessionAgentProcessDidTerminateNotification
  ];

  self.notificationsRecieved = [NSMutableArray array];
  for (NSString *notificationName in notificationNames) {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(notificationRecieved:) name:notificationName object:nil];
  }
}

- (void)tearDown
{
  [NSNotificationCenter.defaultCenter removeObserver:self];
  self.notificationsRecieved = nil;
}

- (void)dealloc
{
  [self tearDown];
}

#pragma mark Notifications

- (void)notificationRecieved:(NSNotification *)notification
{
  [self.notificationsRecieved addObject:notification];
}

- (void)consumeNotification:(NSString *)notificationName
{
  if (self.notificationsRecieved.count == 0) {
    _XCTPrimitiveFail(self.testCase, @"There was no notification to recieve for %@", notificationName);
    return;
  }
  _XCTPrimitiveAssertEqualObjects(self.testCase, notificationName, "notificationName", [self.notificationsRecieved[0] name], "[self.notificationsRecieved[0] name]");
  [self.notificationsRecieved removeObjectAtIndex:0];
}

- (void)noNotificationsToConsume
{
  _XCTPrimitiveAssertEqual(self.testCase, self.notificationsRecieved.count, "self.notificationsRecieved.count",  0, "0", @"Expected to have no notifications to consume but there was %@", self.notificationsRecieved);
}

#pragma mark Interactions

- (void)interactionSuccessful:(id<FBInteraction>)interaction
{
  NSError *error = nil;
  BOOL success = [interaction performInteractionWithError:&error];

  _XCTPrimitiveAssertTrue(self.testCase, success, "assertPerformSuccess:");
  _XCTPrimitiveAssertNil(self.testCase, error, "error");
}

@end
