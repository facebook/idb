/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlAssertions.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

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
    FBSimulatorDidLaunchNotification,
    FBSimulatorDidTerminateNotification,
    FBSimulatorApplicationProcessDidLaunchNotification,
    FBSimulatorApplicationProcessDidTerminateNotification,
    FBSimulatorAgentProcessDidLaunchNotification,
    FBSimulatorAgentProcessDidTerminateNotification,
    FBSimulatorSessionDidStartNotification,
    FBSimulatorSessionDidEndNotification
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

- (NSNotification *)consumeNotification:(NSString *)notificationName
{
  if (self.notificationsRecieved.count == 0) {
    _XCTPrimitiveFail(self.testCase, @"There was no notification to recieve for %@", notificationName);
    return nil;
  }
  NSNotification *actual = self.notificationsRecieved.firstObject;
  _XCTPrimitiveAssertEqualObjects(self.testCase, notificationName, "notificationName", actual.name, "[self.notificationsRecieved[0] name]");
  [self.notificationsRecieved removeObjectAtIndex:0];
  return actual;
}

- (NSNotification *)consumeNotification:(NSString *)notificationName timeout:(NSTimeInterval)timeout
{
  NSNotification *actual = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilExists:^ NSString * {
    if (self.notificationsRecieved == 0) {
      return nil;
    }
    return self.notificationsRecieved.firstObject;
  }];

  if (!actual) {
    _XCTPrimitiveFail(self.testCase, @"There were notifications recieved before timing out");
    return nil;
  }

  _XCTPrimitiveAssertEqualObjects(self.testCase, notificationName, "notificationName", actual.name, "[self.notificationsRecieved[0] name]");
  [self.notificationsRecieved removeObjectAtIndex:0];
  return actual;
}

- (void)consumeAllNotifications
{
  // Spin run loop to filter out any pending notifications.
  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:2 untilTrue:^BOOL{
    return NO;
  }];
  [self.notificationsRecieved removeAllObjects];
}

- (void)noNotificationsToConsume
{
  _XCTPrimitiveAssertEqual(self.testCase, self.notificationsRecieved.count, "self.notificationsRecieved.count", 0u, "0", @"Expected to have no notifications to consume but there was %@", self.notificationsRecieved);
}

#pragma mark Interactions

- (void)interactionSuccessful:(id<FBInteraction>)interaction
{
  NSError *error = nil;
  BOOL success = [interaction performInteractionWithError:&error];

  _XCTPrimitiveAssertNil(self.testCase, error, "error");
  _XCTPrimitiveAssertTrue(self.testCase, success, "interactionSuccessful:");
}

- (void)interactionFailed:(id<FBInteraction>)interaction
{
  NSError *error = nil;
  BOOL success = [interaction performInteractionWithError:&error];

  _XCTPrimitiveAssertFalse(self.testCase, success, "interactionFailed:");
}

#pragma mark Sessions

- (void)shutdownSimulatorAndTerminateSession:(FBSimulatorSession *)session
{
  [self interactionSuccessful:session.interact.shutdownSimulator];

  NSError *error = nil;
  BOOL success = [session terminateWithError:&error];

  _XCTPrimitiveAssertNil(self.testCase, error, "terminationFailed:");
  _XCTPrimitiveAssertTrue(self.testCase, success, "terminationFailed:");
}

#pragma mark Strings

- (void)needle:(NSString *)needle inHaystack:(NSString *)haystack
{
  _XCTPrimitiveAssertNotNil(self.testCase, haystack, "expected needle to exist");
  _XCTPrimitiveAssertNotNil(self.testCase, haystack, "expected haystack exist");
  if ([haystack rangeOfString:needle].location != NSNotFound) {
    return;
  }
  [self.testCase recordFailureWithDescription:[NSString stringWithFormat:@"needle '%@' to be contained in haystack '%@'", needle, haystack] inFile:@(__FILE__) atLine:__LINE__ expected:NO];
}

@end
