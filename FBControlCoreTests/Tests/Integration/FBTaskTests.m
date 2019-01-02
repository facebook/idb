/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreFixtures.h"
#import "FBControlCoreLoggerDouble.h"

@interface FBTaskBuilder (FBTaskTests)

@end

@implementation FBTaskBuilder (FBTaskTests)

- (FBTask *)startSynchronously
{
  FBFuture<FBTask *> *future = [self start];
  NSError *error = nil;
  FBTask *task = [future await:&error];
  NSAssert(task, @"Task Could not be started %@", error);
  return task;
}

@end

@interface FBTaskTests : XCTestCase

@end

@implementation FBTaskTests

- (FBTask *)runAndWaitForTaskFuture:(FBFuture *)future
{
  [[future timeout:FBControlCoreGlobalConfiguration.regularTimeout waitingFor:@"FBTask to complete"] await:NULL];
  return future.result;
}

- (void)testBase64Matches
{
  NSString *filePath = FBControlCoreFixtures.assetsdCrashPathWithCustomDeviceSet;
  NSString *expected = [[NSData dataWithContentsOfFile:filePath] base64EncodedStringWithOptions:0];


  FBFuture *futureTask = [[FBTaskBuilder
    withLaunchPath:@"/usr/bin/base64" arguments:@[@"-i", filePath]]
    runUntilCompletion];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];

  XCTAssertEqual(task.completed.state, FBFutureStateDone);
  XCTAssertEqualObjects(task.stdOut, expected);
  XCTAssertGreaterThan(task.processIdentifier, 1);
}

- (void)testStringsOfCurrentBinary
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];
  NSString *binaryName = [[bundlePath lastPathComponent] stringByDeletingPathExtension];
  NSString *binaryPath = [[bundlePath stringByAppendingPathComponent:@"Contents/MacOS"] stringByAppendingPathComponent:binaryName];

  FBFuture *futureTask = [[FBTaskBuilder
    withLaunchPath:@"/usr/bin/strings" arguments:@[binaryPath]] runUntilCompletion];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];


  XCTAssertEqual(task.completed.state, FBFutureStateDone);
  XCTAssertTrue([task.stdOut containsString:NSStringFromSelector(_cmd)]);
  XCTAssertGreaterThan(task.processIdentifier, 1);
}

- (void)testBundleContents
{
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  NSString *resourcesPath = [[bundle bundlePath] stringByAppendingPathComponent:@"Contents/Resources"];

  FBFuture *futureTask = [[FBTaskBuilder
    withLaunchPath:@"/bin/ls" arguments:@[@"-1", resourcesPath]] runUntilCompletion];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];

  XCTAssertEqual(task.completed.state, FBFutureStateDone);
  XCTAssertGreaterThan(task.processIdentifier, 1);

  NSArray<NSString *> *fileNames = [task.stdOut componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  XCTAssertGreaterThanOrEqual(fileNames.count, 2u);

  for (NSString *fileName in fileNames) {
    NSString *path = [bundle pathForResource:fileName ofType:nil];
    XCTAssertNotNil(path);
  }
}

- (void)testLineReader
{
  NSString *filePath = FBControlCoreFixtures.assetsdCrashPathWithCustomDeviceSet;
  NSMutableArray<NSString *> *lines = [NSMutableArray array];

  FBFuture *futureTask = [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/grep" arguments:@[@"CoreFoundation", filePath]]
    withStdOutLineReader:^(NSString *line) {
      [lines addObject:line];
    }]
  runUntilCompletion];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];

  XCTAssertEqual(task.completed.state, FBFutureStateDone);
  XCTAssertTrue([task.stdOut conformsToProtocol:@protocol(FBFileConsumer)]);
  XCTAssertGreaterThan(task.processIdentifier, 1);

  [[[FBFuture futureWithResult:NSNull.null] delay:2] await:nil];
  XCTAssertEqual(lines.count, 8u);
  XCTAssertEqualObjects(lines[0], @"0   CoreFoundation                      0x0138ba14 __exceptionPreprocess + 180");
}

- (void)testLogger
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];

  FBFuture *futureTask = [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/file" arguments:@[bundlePath]]
    withStdErrToLogger:[FBControlCoreLoggerDouble new]]
    withStdOutToLogger:[FBControlCoreLoggerDouble new]]
    runUntilCompletion];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];

  XCTAssertEqual(task.completed.state, FBFutureStateDone);
  XCTAssertTrue([task.stdOut isKindOfClass:FBControlCoreLoggerDouble.class]);
  XCTAssertTrue([task.stdErr isKindOfClass:FBControlCoreLoggerDouble.class]);
}

- (void)testDevNull
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];

  FBFuture *futureTask = [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/file" arguments:@[bundlePath]]
    withStdOutToDevNull]
    withStdErrToDevNull]
    runUntilCompletion];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];

  XCTAssertEqual(task.completed.state, FBFutureStateDone);
  XCTAssertNil(task.stdOut);
  XCTAssertNil(task.stdErr);
}

- (void)testUpdatesStateWithAsynchronousTermination
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1"]]
    startSynchronously];

  NSError *error = nil;
  BOOL success = [task.completed awaitWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (void)testAwaitingTerminationOfShortLivedProcess
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"0"]]
    startSynchronously];

  XCTAssertNotNil([task.completed awaitWithTimeout:1 error:nil]);
  XCTAssertEqual(task.completed.state, FBFutureStateDone);
}

- (void)testCallsHandlerWithAsynchronousTermination
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Termination Handler Called"];
  [[[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1"]]
    runUntilCompletion]
    onQueue:dispatch_get_main_queue() notifyOfCompletion:^(id _) {
      [expectation fulfill];
    }];

  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testAwaitingTerminationDoesNotTerminateStalledTask
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Termination Handler Called"];
  expectation.inverted = YES;
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000"]]
    startSynchronously];

  [task.completed onQueue:dispatch_get_main_queue() notifyOfCompletion:^(id _) {
    [expectation fulfill];
  }];

  NSError *error = nil;
  BOOL waitSuccess = [task.completed awaitWithTimeout:2 error:&error] != nil;
  XCTAssertFalse(waitSuccess);
  XCTAssertNotNil(error);
  XCTAssertFalse(task.completed.hasCompleted);

  [self waitForExpectations:@[expectation] timeout:2];
}

- (void)testInputReading
{
  NSData *expected = [@"FOO BAR BAZ" dataUsingEncoding:NSUTF8StringEncoding];

  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:@"/bin/cat" arguments:@[]]
    withStdInConnected]
    withStdOutInMemoryAsData]
    withStdErrToDevNull]
    startSynchronously];

  XCTAssertTrue([task.stdIn conformsToProtocol:@protocol(FBFileConsumer)]);
  [task.stdIn consumeData:expected];
  [task.stdIn consumeEndOfFile];

  NSError *error = nil;
  BOOL waitSuccess = [task.completed awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);

  XCTAssertEqualObjects(expected, task.stdOut);
}

- (void)testInputFromData
{
  NSData *expected = [@"FOO BAR BAZ" dataUsingEncoding:NSUTF8StringEncoding];

  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:@"/bin/cat" arguments:@[]]
    withStdInFromData:expected]
    withStdOutInMemoryAsData]
    withStdErrToDevNull]
    startSynchronously];

  NSError *error = nil;
  BOOL waitSuccess = [task.completed awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);

  XCTAssertEqualObjects(expected, task.stdOut);
}

- (void)testCancellationIsSignalling
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000000"]]
    startSynchronously];

  XCTAssertEqual(task.completed.state, FBFutureStateRunning);
  XCTAssertEqual(task.exitCode.state, FBFutureStateRunning);

  NSError *error = nil;
  BOOL success = [[task.completed cancel] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(task.completed.state, FBFutureStateCancelled);
  XCTAssertEqual(task.exitCode.state, FBFutureStateDone);
  XCTAssertEqualObjects(task.exitCode.result, @(SIGTERM));
}

- (void)testSendingSIGINT
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000000"]]
    startSynchronously];

  XCTAssertEqual(task.completed.state, FBFutureStateRunning);
  XCTAssertEqual(task.exitCode.state, FBFutureStateRunning);

  NSError *error = nil;
  BOOL success = [[task sendSignal:SIGINT] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(task.completed.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateDone);
  XCTAssertEqualObjects(task.exitCode.result, @(SIGINT));
}

- (void)testSendingSIGKILL
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000000"]]
    startSynchronously];

  XCTAssertEqual(task.completed.state, FBFutureStateRunning);
  XCTAssertEqual(task.exitCode.state, FBFutureStateRunning);

  NSError *error = nil;
  BOOL success = [[task sendSignal:SIGKILL] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(task.completed.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateDone);
  XCTAssertEqualObjects(task.exitCode.result, @(SIGKILL));
}

- (void)testHUPBackoffToKILL
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/usr/bin/nohup" arguments:@[@"/bin/sleep", @"10000000"]]
    startSynchronously];

  XCTAssertEqual(task.completed.state, FBFutureStateRunning);
  XCTAssertEqual(task.exitCode.state, FBFutureStateRunning);

  NSError *error = nil;
  BOOL success = [[task sendSignal:SIGHUP backingOfToKillWithTimeout:0.5] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(task.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.result, @(SIGKILL));

  success = [task.completed await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(task.completed.state, FBFutureStateDone);
}

@end
