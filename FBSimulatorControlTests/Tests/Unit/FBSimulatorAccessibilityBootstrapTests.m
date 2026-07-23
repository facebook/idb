/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import "FBSimulatorAccessibilityBootstrapTesting.h"

@interface FBSimulatorAccessibilityBootstrapTestDevice : NSObject
@end

@implementation FBSimulatorAccessibilityBootstrapTestDevice
@end

@interface FBSimulatorAccessibilityBootstrapSimulatorSocketProvider : NSObject
@end

@implementation FBSimulatorAccessibilityBootstrapSimulatorSocketProvider

+ (id)connectionProviderForSimDevice:(id)simulatorDevice
{
  return [NSObject new];
}

@end

@interface FBSimulatorAccessibilityBootstrapUnavailableProvider : NSObject
@end

@implementation FBSimulatorAccessibilityBootstrapUnavailableProvider
@end

static NSError *FBSimulatorAccessibilityBootstrapSessionError;
static NSError *FBSimulatorAccessibilityBootstrapLoadError;
static void (^FBSimulatorAccessibilityBootstrapPendingSessionCompletion)(id, NSError *);

@interface FBSimulatorAccessibilityBootstrapSuccessfulSession : NSObject

@property (nonatomic, assign) BOOL invalidated;

@end

@implementation FBSimulatorAccessibilityBootstrapSuccessfulSession

- (void)loadAccessibilityWithTimeout:(NSTimeInterval)timeout reply:(void (^)(BOOL, NSError *))reply
{
  reply(YES, nil);
}

- (void)invalidate
{
  self.invalidated = YES;
}

@end

@interface FBSimulatorAccessibilityBootstrapFailingLoadSession : FBSimulatorAccessibilityBootstrapSuccessfulSession
@end

@implementation FBSimulatorAccessibilityBootstrapFailingLoadSession

- (void)loadAccessibilityWithTimeout:(NSTimeInterval)timeout reply:(void (^)(BOOL, NSError *))reply
{
  reply(NO, FBSimulatorAccessibilityBootstrapLoadError);
}

@end

@interface FBSimulatorAccessibilityBootstrapSuccessfulSessionRequester : NSObject
@end

@implementation FBSimulatorAccessibilityBootstrapSuccessfulSessionRequester

+ (void)requestSessionWithDaemonConnectionProvider:(id)provider completion:(void (^)(id, NSError *))completion
{
  completion([FBSimulatorAccessibilityBootstrapSuccessfulSession new], nil);
}

@end

@interface FBSimulatorAccessibilityBootstrapFailingSessionRequester : NSObject
@end

@implementation FBSimulatorAccessibilityBootstrapFailingSessionRequester

+ (void)requestSessionWithDaemonConnectionProvider:(id)provider completion:(void (^)(id, NSError *))completion
{
  completion(nil, FBSimulatorAccessibilityBootstrapSessionError);
}

@end

@interface FBSimulatorAccessibilityBootstrapFailingLoadSessionRequester : NSObject
@end

@implementation FBSimulatorAccessibilityBootstrapFailingLoadSessionRequester

+ (void)requestSessionWithDaemonConnectionProvider:(id)provider completion:(void (^)(id, NSError *))completion
{
  completion([FBSimulatorAccessibilityBootstrapFailingLoadSession new], nil);
}

@end

@interface FBSimulatorAccessibilityBootstrapPendingSessionRequester : NSObject
@end

@implementation FBSimulatorAccessibilityBootstrapPendingSessionRequester

+ (void)requestSessionWithDaemonConnectionProvider:(id)provider completion:(void (^)(id, NSError *))completion
{
  FBSimulatorAccessibilityBootstrapPendingSessionCompletion = [completion copy];
}

@end

@interface FBSimulatorAccessibilityBootstrapTests : XCTestCase
@end

@implementation FBSimulatorAccessibilityBootstrapTests

- (void)setUp
{
  [super setUp];
  FBSimulatorAccessibilityBootstrapSessionError = nil;
  FBSimulatorAccessibilityBootstrapLoadError = nil;
  FBSimulatorAccessibilityBootstrapPendingSessionCompletion = nil;
}

- (void)testReportsMissingProvider
{
  NSError *error = nil;

  BOOL succeeded = [FBSimulatorControlFrameworkLoader performAccessibilityBootstrapForSimulatorDevice:[FBSimulatorAccessibilityBootstrapTestDevice new]
                                                                                               timeout:1
                                                                                                logger:nil
                                                                                         providerClass:FBSimulatorAccessibilityBootstrapUnavailableProvider.class
                                                                                          sessionClass:FBSimulatorAccessibilityBootstrapSuccessfulSessionRequester.class
                                                                                        loadFrameworks:NO
                                                                                                 error:&error];

  XCTAssertFalse(succeeded);
  XCTAssertEqualObjects(error.domain, @"com.facebook.FBSimulatorControl.AccessibilityBootstrap");
  XCTAssertTrue([error.localizedDescription containsString:@"unavailable"]);
}

- (void)testPreservesSessionCreationError
{
  NSError *underlyingError = [NSError errorWithDomain:@"Session" code:42 userInfo:@{NSLocalizedDescriptionKey: @"Session failed"}];
  FBSimulatorAccessibilityBootstrapSessionError = underlyingError;
  NSError *error = nil;

  BOOL succeeded = [FBSimulatorControlFrameworkLoader performAccessibilityBootstrapForSimulatorDevice:[FBSimulatorAccessibilityBootstrapTestDevice new]
                                                                                               timeout:1
                                                                                                logger:nil
                                                                                         providerClass:FBSimulatorAccessibilityBootstrapSimulatorSocketProvider.class
                                                                                          sessionClass:FBSimulatorAccessibilityBootstrapFailingSessionRequester.class
                                                                                        loadFrameworks:NO
                                                                                                 error:&error];

  XCTAssertFalse(succeeded);
  XCTAssertEqual(error, underlyingError);
}

- (void)testPreservesAccessibilityLoadError
{
  NSError *underlyingError = [NSError errorWithDomain:@"Accessibility" code:43 userInfo:@{NSLocalizedDescriptionKey: @"Load failed"}];
  FBSimulatorAccessibilityBootstrapLoadError = underlyingError;
  NSError *error = nil;

  BOOL succeeded = [FBSimulatorControlFrameworkLoader performAccessibilityBootstrapForSimulatorDevice:[FBSimulatorAccessibilityBootstrapTestDevice new]
                                                                                               timeout:1
                                                                                                logger:nil
                                                                                         providerClass:FBSimulatorAccessibilityBootstrapSimulatorSocketProvider.class
                                                                                          sessionClass:FBSimulatorAccessibilityBootstrapFailingLoadSessionRequester.class
                                                                                        loadFrameworks:NO
                                                                                                 error:&error];

  XCTAssertFalse(succeeded);
  XCTAssertEqual(error, underlyingError);
}

- (void)testBoundsSessionCreationAndInvalidatesLateSession
{
  NSError *error = nil;

  BOOL succeeded = [FBSimulatorControlFrameworkLoader performAccessibilityBootstrapForSimulatorDevice:[FBSimulatorAccessibilityBootstrapTestDevice new]
                                                                                               timeout:0.01
                                                                                                logger:nil
                                                                                         providerClass:FBSimulatorAccessibilityBootstrapSimulatorSocketProvider.class
                                                                                          sessionClass:FBSimulatorAccessibilityBootstrapPendingSessionRequester.class
                                                                                        loadFrameworks:NO
                                                                                                 error:&error];

  XCTAssertFalse(succeeded);
  XCTAssertTrue([error.localizedDescription containsString:@"Timed out creating"]);
  XCTAssertNotNil(FBSimulatorAccessibilityBootstrapPendingSessionCompletion);

  FBSimulatorAccessibilityBootstrapSuccessfulSession *lateSession = [FBSimulatorAccessibilityBootstrapSuccessfulSession new];
  FBSimulatorAccessibilityBootstrapPendingSessionCompletion(lateSession, nil);
  XCTAssertTrue(lateSession.invalidated);
}

- (void)testCoalescesConcurrentBootstrapAttempts
{
  FBSimulatorAccessibilityBootstrapTestDevice *device = [FBSimulatorAccessibilityBootstrapTestDevice new];
  dispatch_semaphore_t releasePerformer = dispatch_semaphore_create(0);
  XCTestExpectation *ownerJoined = [self expectationWithDescription:@"Owner joined"];
  XCTestExpectation *followerJoined = [self expectationWithDescription:@"Follower joined"];
  XCTestExpectation *completed = [self expectationWithDescription:@"Both calls completed"];
  completed.expectedFulfillmentCount = 2;
  __block NSUInteger performerCount = 0;
  __block BOOL ownerSucceeded = NO;
  __block BOOL followerSucceeded = NO;
  FBSimulatorAccessibilityBootstrapPerformer performer = ^BOOL(id simulatorDevice, NSTimeInterval timeout, id<FBControlCoreLogger> logger, NSError **error) {
    @synchronized (device) {
      performerCount += 1;
    }
    return dispatch_semaphore_wait(releasePerformer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0;
  };

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    ownerSucceeded = [FBSimulatorControlFrameworkLoader bootstrapAccessibilityForSimulatorDevice:device
                                                                                         timeout:1
                                                                                          logger:nil
                                                                                       performer:performer
                                                                                 attemptObserver:^(BOOL ownsAttempt) {
      XCTAssertTrue(ownsAttempt);
      [ownerJoined fulfill];
    }
                                                                                           error:nil];
    [completed fulfill];
  });
  [self waitForExpectations:@[ownerJoined] timeout:1];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    followerSucceeded = [FBSimulatorControlFrameworkLoader bootstrapAccessibilityForSimulatorDevice:device
                                                                                            timeout:1
                                                                                             logger:nil
                                                                                          performer:performer
                                                                                    attemptObserver:^(BOOL ownsAttempt) {
      XCTAssertFalse(ownsAttempt);
      [followerJoined fulfill];
    }
                                                                                              error:nil];
    [completed fulfill];
  });
  [self waitForExpectations:@[followerJoined] timeout:1];
  dispatch_semaphore_signal(releasePerformer);
  [self waitForExpectations:@[completed] timeout:1];

  XCTAssertEqual(performerCount, 1u);
  XCTAssertTrue(ownerSucceeded);
  XCTAssertTrue(followerSucceeded);
}

- (void)testBoundsWaitForCoalescedAttempt
{
  FBSimulatorAccessibilityBootstrapTestDevice *device = [FBSimulatorAccessibilityBootstrapTestDevice new];
  dispatch_semaphore_t releasePerformer = dispatch_semaphore_create(0);
  XCTestExpectation *ownerJoined = [self expectationWithDescription:@"Owner joined"];
  XCTestExpectation *ownerCompleted = [self expectationWithDescription:@"Owner completed"];
  FBSimulatorAccessibilityBootstrapPerformer performer = ^BOOL(id simulatorDevice, NSTimeInterval timeout, id<FBControlCoreLogger> logger, NSError **error) {
    return dispatch_semaphore_wait(releasePerformer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0;
  };

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [FBSimulatorControlFrameworkLoader bootstrapAccessibilityForSimulatorDevice:device
                                                                        timeout:1
                                                                         logger:nil
                                                                      performer:performer
                                                                attemptObserver:^(BOOL ownsAttempt) {
      XCTAssertTrue(ownsAttempt);
      [ownerJoined fulfill];
    }
                                                                          error:nil];
    [ownerCompleted fulfill];
  });
  [self waitForExpectations:@[ownerJoined] timeout:1];

  __block BOOL followerJoined = NO;
  NSError *error = nil;
  BOOL followerSucceeded = [FBSimulatorControlFrameworkLoader bootstrapAccessibilityForSimulatorDevice:device
                                                                                                timeout:0.01
                                                                                                 logger:nil
                                                                                              performer:performer
                                                                                        attemptObserver:^(BOOL ownsAttempt) {
    followerJoined = !ownsAttempt;
  }
                                                                                                  error:&error];

  XCTAssertTrue(followerJoined);
  XCTAssertFalse(followerSucceeded);
  XCTAssertTrue([error.localizedDescription containsString:@"Timed out waiting"]);
  dispatch_semaphore_signal(releasePerformer);
  [self waitForExpectations:@[ownerCompleted] timeout:1];
}

@end
