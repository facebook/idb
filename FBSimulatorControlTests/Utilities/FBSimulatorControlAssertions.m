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

@implementation XCTestCase (FBSimulatorControlAssertions)

#pragma mark Interactions

- (void)assertInteractionSuccessful:(id<FBInteraction>)interaction
{
  NSError *error = nil;
  BOOL success = [interaction performInteractionWithError:&error];

  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (void)assertInteractionFailed:(id<FBInteraction>)interaction
{
  NSError *error = nil;
  BOOL success = [interaction performInteractionWithError:&error];
  XCTAssertFalse(success);
}

#pragma mark Sessions

- (void)assertShutdownSimulatorAndTerminateSession:(FBSimulatorSession *)session
{
  [self assertInteractionSuccessful:session.interact.shutdownSimulator];

  NSError *error = nil;
  BOOL success = [session terminateWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

#pragma mark Strings

- (void)assertNeedle:(NSString *)needle inHaystack:(NSString *)haystack
{
  XCTAssertNotNil(needle);
  XCTAssertNotNil(haystack);
  if ([haystack rangeOfString:needle].location != NSNotFound) {
    return;
  }
  XCTFail(@"needle '%@' to be contained in haystack '%@'", needle, haystack);
}

@end

@interface FBSimulatorControlNotificationAssertions ()

@property (nonatomic, strong, readonly) NSMutableArray *notificationsRecieved;
@property (nonatomic, weak, readonly) XCTestCase *testCase;
@property (nonatomic, weak, readonly) FBSimulatorPool *pool;

@end

@implementation FBSimulatorControlNotificationAssertions

+ (instancetype)withTestCase:(XCTestCase *)testCase pool:(FBSimulatorPool *)pool
{
  return [[self alloc] initWithTestCase:testCase pool:pool];
}

- (instancetype)initWithTestCase:(XCTestCase *)testCase  pool:(FBSimulatorPool *)pool
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _pool = pool;
  _testCase = testCase;
  _notificationsRecieved = [NSMutableArray array];
  [self registerNotificationObservers];

  return self;
}

- (void)registerNotificationObservers
{
  NSArray *notificationNames = @[
    FBSimulatorDidLaunchNotification,
    FBSimulatorDidTerminateNotification,
    FBSimulatorApplicationProcessDidLaunchNotification,
    FBSimulatorApplicationProcessDidTerminateNotification,
    FBSimulatorAgentProcessDidLaunchNotification,
    FBSimulatorAgentProcessDidTerminateNotification,
  ];
  for (NSString *notificationName in notificationNames) {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(simulatorNotificationRecieved:) name:notificationName object:nil];
  }

  notificationNames = @[
    FBSimulatorSessionDidStartNotification,
    FBSimulatorSessionDidEndNotification
  ];
  for (NSString *notificationName in notificationNames) {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sessionNotificationReceieved:) name:notificationName object:nil];
  }
}

- (void)tearDown
{
  [NSNotificationCenter.defaultCenter removeObserver:self];
  [self.notificationsRecieved removeAllObjects];
}

- (void)dealloc
{
  [self tearDown];
}

#pragma mark Notifications

- (void)sessionNotificationReceieved:(NSNotification *)notification
{
  [self.notificationsRecieved addObject:notification];
}

- (void)simulatorNotificationRecieved:(NSNotification *)notification
{
  FBSimulator *simulator = notification.object;
  if (simulator.pool != self.pool) {
    return;
  }
  [self.notificationsRecieved addObject:notification];
}

- (NSNotification *)consumeNotification:(NSString *)notificationName
{
  if (self.notificationsRecieved.count == 0) {
    [self failOnLine:__LINE__ withFormat:@"There was no notification to recieve for %@", notificationName];
    return nil;
  }
  NSNotification *actual = self.notificationsRecieved.firstObject;
  [self failIfFalse:[notificationName isEqualToString:actual.name] line:__LINE__ withFormat:@"Expected Notification %@ to be sent but got %@", notificationName, self.notificationsRecieved];
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
    [self failOnLine:__LINE__ withFormat:@"There were notifications recieved before timing out when waiting for %@", notificationName];
    return nil;
  }

  [self failIfFalse:[notificationName isEqualToString:actual.name] line:__LINE__ withFormat:@"Expected Notification %@ to be sent but got %@", notificationName, self.notificationsRecieved];
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
  // Spin run loop to filter out any pending notifications.
  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:2 untilTrue:^BOOL{
    return NO;
  }];
  [self failIfFalse:(self.notificationsRecieved.count == 0) line:__LINE__ withFormat:@"Expected no notifications but got %@", self.notificationsRecieved];
}

#pragma mark Helpers

- (void)failIfFalse:(BOOL)value line:(NSUInteger)line withFormat:(NSString *)format, ...
{
  if (value) {
    return;
  }

  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  [self.testCase recordFailureWithDescription:string inFile:@(__FILE__) atLine:line expected:YES];
}

- (void)failOnLine:(NSUInteger)line withFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  [self.testCase recordFailureWithDescription:string inFile:@(__FILE__) atLine:line expected:YES];
}

@end
