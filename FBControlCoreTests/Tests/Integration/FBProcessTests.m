/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreFixtures.h"
#import "FBControlCoreLoggerDouble.h"

@interface FBProcessBuilder (FBProcessTests)

@end

@implementation FBProcessBuilder (FBProcessTests)

- (FBIDBProcess *)startSynchronously
{
  FBFuture<FBIDBProcess *> *future = [self start];
  NSError *error = nil;
  FBIDBProcess *process = [future await:&error];
  NSAssert(process, @"Task Could not be started %@", error);
  return process;
}

@end

@interface FBProcessTests : XCTestCase

@end

@implementation FBProcessTests

- (FBIDBProcess *)runAndWaitForTaskFuture:(FBFuture *)future
{
  [[future timeout:FBControlCoreGlobalConfiguration.regularTimeout waitingFor:@"FBTask to complete"] await:NULL];
  return future.result;
}

- (void)testTrueExit
{
  FBFuture *futureProcess = [[[FBProcessBuilder
    withLaunchPath:@"/bin/sh" arguments:@[@"-c", @"true"]]
    withTaskLifecycleLoggingTo:FBControlCoreGlobalConfiguration.defaultLogger]
    runUntilCompletionWithAcceptableExitCodes:nil];

  FBIDBProcess *process = [self runAndWaitForTaskFuture:futureProcess];

  XCTAssertEqualObjects(process.exitCode.result, @0);
}

- (void)testFalseExit
{
  FBFuture *futureProcess = [[FBProcessBuilder
    withLaunchPath:@"/bin/sh" arguments:@[@"-c", @"false"]]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@1]];

  FBIDBProcess *process = [self runAndWaitForTaskFuture:futureProcess];
  XCTAssertEqualObjects(process.exitCode.result, @1);
}

- (void)testFalseExitWithStatusCodeError
{
  NSError *error = nil;
  id result = [[[FBProcessBuilder
    withLaunchPath:@"/bin/sh" arguments:@[@"-c", @"false"]]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    await:&error];

  XCTAssertNil(result);
  XCTAssertNotNil(error);
}

- (void)testEnvironment
{
  NSDictionary<NSString *, NSString *> *environment = @{
    @"FOO0": @"BAR0",
    @"FOO1": @"BAR1",
    @"FOO2": @"BAR2",
    @"FOO3": @"BAR3",
    @"FOO4": @"BAR4",
  };
  FBFuture *futureProcess = [[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/env"]
    withEnvironment:environment]
    runUntilCompletionWithAcceptableExitCodes:nil];

  FBIDBProcess *process = [self runAndWaitForTaskFuture:futureProcess];
  XCTAssertEqualObjects(process.exitCode.result, @0);
  for (NSString *key in environment.allKeys) {
    NSString *expected = [NSString stringWithFormat:@"%@=%@", key, environment[key]];
    XCTAssertTrue([process.stdOut containsString:expected]);
  }
}

- (void)testBase64Matches
{
  NSString *filePath = FBControlCoreFixtures.assetsdCrashPathWithCustomDeviceSet;
  NSString *expected = [[NSData dataWithContentsOfFile:filePath] base64EncodedStringWithOptions:0];

  FBFuture *futureProcess = [[FBProcessBuilder
    withLaunchPath:@"/usr/bin/base64" arguments:@[@"-i", filePath]]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBIDBProcess *process = [self runAndWaitForTaskFuture:futureProcess];

  XCTAssertEqual(process.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(process.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(process.signal.state, FBFutureStateFailed);
  XCTAssertEqualObjects(process.stdOut, expected);
  XCTAssertGreaterThan(process.processIdentifier, 1);
}

- (void)testStringsOfCurrentBinary
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];
  NSString *binaryName = [[bundlePath lastPathComponent] stringByDeletingPathExtension];
  NSString *binaryPath = [[bundlePath stringByAppendingPathComponent:@"Contents/MacOS"] stringByAppendingPathComponent:binaryName];

  FBFuture *futureProcess = [[FBProcessBuilder
    withLaunchPath:@"/usr/bin/strings" arguments:@[binaryPath]]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBIDBProcess *process = [self runAndWaitForTaskFuture:futureProcess];


  XCTAssertEqual(process.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(process.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(process.signal.state, FBFutureStateFailed);
  XCTAssertTrue([process.stdOut containsString:NSStringFromSelector(_cmd)]);
  XCTAssertGreaterThan(process.processIdentifier, 1);
}

- (void)testBundleContents
{
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  NSString *resourcesPath = [[bundle bundlePath] stringByAppendingPathComponent:@"Contents/Resources"];

  FBFuture *futureProcess = [[FBProcessBuilder
    withLaunchPath:@"/bin/ls" arguments:@[@"-1", resourcesPath]]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBIDBProcess *process = [self runAndWaitForTaskFuture:futureProcess];

  XCTAssertEqual(process.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(process.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(process.signal.state, FBFutureStateFailed);
  XCTAssertGreaterThan(process.processIdentifier, 1);

  NSArray<NSString *> *fileNames = [process.stdOut componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
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

  FBFuture *futureProcess = [[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/grep" arguments:@[@"CoreFoundation", filePath]]
    withStdOutLineReader:^(NSString *line) {
      [lines addObject:line];
    }]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBIDBProcess *process = [self runAndWaitForTaskFuture:futureProcess];

  XCTAssertEqual(process.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(process.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(process.signal.state, FBFutureStateFailed);
  XCTAssertTrue([process.stdOut conformsToProtocol:@protocol(FBDataConsumer)]);
  XCTAssertGreaterThan(process.processIdentifier, 1);

  [[FBFuture.empty delay:2] await:nil];
  XCTAssertEqual(lines.count, 8u);
  XCTAssertEqualObjects(lines[0], @"0   CoreFoundation                      0x0138ba14 __exceptionPreprocess + 180");
}

- (void)testLogger
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];

  FBFuture *futureProcess = [[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/file" arguments:@[bundlePath]]
    withStdErrToLogger:[FBControlCoreLoggerDouble new]]
    withStdOutToLogger:[FBControlCoreLoggerDouble new]]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBIDBProcess *process = [self runAndWaitForTaskFuture:futureProcess];

  XCTAssertEqual(process.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(process.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(process.signal.state, FBFutureStateFailed);
  XCTAssertTrue([process.stdOut isKindOfClass:FBControlCoreLoggerDouble.class]);
  XCTAssertTrue([process.stdErr isKindOfClass:FBControlCoreLoggerDouble.class]);
}

- (void)testDevNull
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];

  FBFuture *futureProcess = [[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/file" arguments:@[bundlePath]]
    withStdOutToDevNull]
    withStdErrToDevNull]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBIDBProcess *process = [self runAndWaitForTaskFuture:futureProcess];

  XCTAssertEqual(process.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(process.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(process.signal.state, FBFutureStateFailed);
  XCTAssertNil(process.stdOut);
  XCTAssertNil(process.stdErr);
}

- (void)testUpdatesStateWithAsynchronousTermination
{
  FBIDBProcess *process = [[FBIDBProcessBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1"]]
    startSynchronously];

  NSError *error = nil;
  BOOL success = [process.exitCode awaitWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (void)testAwaitingTerminationOfShortLivedProcess
{
  FBIDBProcess *process = [[FBIDBProcessBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"0"]]
    startSynchronously];

  XCTAssertNotNil([process.exitCode awaitWithTimeout:1 error:nil]);
  XCTAssertEqual(process.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(process.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(process.signal.state, FBFutureStateFailed);
}

- (void)testCallsHandlerWithAsynchronousTermination
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Termination Handler Called"];
  [[[FBProcessBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1"]]
    runUntilCompletionWithAcceptableExitCodes:nil]
    onQueue:dispatch_get_main_queue() notifyOfCompletion:^(id _) {
      [expectation fulfill];
    }];

  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testAwaitingTerminationDoesNotTerminateStalledTask
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Termination Handler Called"];
  expectation.inverted = YES;
  FBIDBProcess *process = [[FBIDBProcessBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000"]]
    startSynchronously];

  [process.statLoc onQueue:dispatch_get_main_queue() notifyOfCompletion:^(id _) {
    [expectation fulfill];
  }];

  NSError *error = nil;
  BOOL waitSuccess = [process.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertFalse(waitSuccess);
  XCTAssertNotNil(error);
  XCTAssertFalse(process.statLoc.hasCompleted);
  XCTAssertFalse(process.exitCode.hasCompleted);
  XCTAssertFalse(process.signal.hasCompleted);

  [self waitForExpectations:@[expectation] timeout:2];
}

- (void)testInputReading
{
  NSData *expected = [@"FOO BAR BAZ" dataUsingEncoding:NSUTF8StringEncoding];

  FBIDBProcess *process = [[[[[FBIDBProcessBuilder
    withLaunchPath:@"/bin/cat" arguments:@[]]
    withStdInConnected]
    withStdOutInMemoryAsData]
    withStdErrToDevNull]
    startSynchronously];

  XCTAssertTrue([process.stdIn conformsToProtocol:@protocol(FBDataConsumer)]);
  [process.stdIn consumeData:expected];
  [process.stdIn consumeEndOfFile];

  NSError *error = nil;
  BOOL waitSuccess = [process.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);

  XCTAssertEqualObjects(expected, process.stdOut);
}

- (void)testInputStream
{
  NSString *expected = @"FOO BAR BAZ";

  FBProcessInput<NSOutputStream *> *input = FBProcessInput.inputFromStream;
  NSOutputStream *stream = input.contents;

  FBIDBProcess *process = [[[[[FBIDBProcessBuilder
    withLaunchPath:@"/bin/cat" arguments:@[]]
    withStdIn:input]
    withStdOutInMemoryAsString]
    withStdErrToDevNull]
    startSynchronously];

  XCTAssertTrue([stream isKindOfClass:NSOutputStream.class]);
  XCTAssertTrue([process.stdIn isKindOfClass:NSOutputStream.class]);
  [stream open];
  [stream write:(const uint8_t *)expected.UTF8String maxLength:strlen(expected.UTF8String)];
  [stream close];

  NSError *error = nil;
  BOOL waitSuccess = [process.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);

  XCTAssertEqualObjects(expected, process.stdOut);
}

- (void)testInputStreamWithBrokenPipe
{
  NSString *expected = @"FOO BAR BAZ";

  FBProcessInput<NSOutputStream *> *input = FBProcessInput.inputFromStream;
  NSOutputStream *stream = input.contents;

  FBIDBProcess *process = [[[[[FBIDBProcessBuilder
    withLaunchPath:@"/bin/cat" arguments:@[]]
    withStdIn:input]
    withStdOutInMemoryAsString]
    withStdErrToDevNull]
    startSynchronously];

  XCTAssertTrue([stream isKindOfClass:NSOutputStream.class]);
  XCTAssertTrue([process.stdIn isKindOfClass:NSOutputStream.class]);
  [stream open];
  [stream write:(const uint8_t *)expected.UTF8String maxLength:strlen(expected.UTF8String)];
  [stream close];

  XCTAssertEqual([stream write:(const uint8_t *)expected.UTF8String maxLength:strlen(expected.UTF8String)], -1);
  XCTAssertNotNil(stream.streamError);

  NSError *error = nil;
  BOOL waitSuccess = [process.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);

  XCTAssertEqualObjects(expected, process.stdOut);
}

- (void)testOutputStream
{
  NSString *expected = @"FOO BAR BAZ";

  FBIDBProcess *process = [[[[FBIDBProcessBuilder
    withLaunchPath:@"/bin/echo" arguments:@[@"FOO BAR BAZ"]]
    withStdErrToDevNull]
    withStdOutToInputStream]
    startSynchronously];

  NSInputStream *stream = process.stdOut;
  XCTAssertTrue([stream isKindOfClass:NSInputStream.class]);
  [stream open];

  NSMutableData *output = NSMutableData.data;
  while (true) {
    uint8 buffer[8];
    NSInteger result = [stream read:buffer maxLength:8];
    if (result < 1) {
      break;
    }
    [output appendBytes:buffer length:(NSUInteger)result];
  }
  NSString *actual = [[[NSString alloc] initWithData:output encoding:NSASCIIStringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
  XCTAssertEqualObjects(expected, actual);

  NSError *error = nil;
  BOOL waitSuccess = [process.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);
}

- (void)testInputFromData
{
  NSData *expected = [@"FOO BAR BAZ" dataUsingEncoding:NSUTF8StringEncoding];

  FBIDBProcess *process = [[[[[FBIDBProcessBuilder
    withLaunchPath:@"/bin/cat" arguments:@[]]
    withStdInFromData:expected]
    withStdOutInMemoryAsData]
    withStdErrToDevNull]
    startSynchronously];

  NSError *error = nil;
  BOOL waitSuccess = [process.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);

  XCTAssertEqualObjects(expected, process.stdOut);
}

- (void)testSendingSIGINT
{
  FBIDBProcess *process = [[FBIDBProcessBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000000"]]
    startSynchronously];

  XCTAssertEqual(process.statLoc.state, FBFutureStateRunning);
  XCTAssertEqual(process.exitCode.state, FBFutureStateRunning);
  XCTAssertEqual(process.signal.state, FBFutureStateRunning);

  NSError *error = nil;
  FBFuture *future = [process sendSignal:SIGINT];
  BOOL success = [future await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(process.exitCode.state, FBFutureStateFailed);
  XCTAssertEqual(process.signal.state, FBFutureStateDone);
  XCTAssertEqualObjects(process.signal.result, @(SIGINT));
}

- (void)testSendingSIGKILL
{
  FBIDBProcess *process = [[FBIDBProcessBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000000"]]
    startSynchronously];

  XCTAssertEqual(process.statLoc.state, FBFutureStateRunning);
  XCTAssertEqual(process.exitCode.state, FBFutureStateRunning);
  XCTAssertEqual(process.signal.state, FBFutureStateRunning);

  NSError *error = nil;
  BOOL success = [[process sendSignal:SIGKILL] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(process.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(process.exitCode.state, FBFutureStateFailed);
  XCTAssertEqual(process.signal.state, FBFutureStateDone);
  XCTAssertEqualObjects(process.signal.result, @(SIGKILL));
}

- (void)testHUPBackoffToKILL
{
  FBIDBProcess *process = [[FBIDBProcessBuilder
    withLaunchPath:@"/usr/bin/nohup" arguments:@[@"/bin/sleep", @"10000000"]]
    startSynchronously];

  XCTAssertEqual(process.statLoc.state, FBFutureStateRunning);
  XCTAssertEqual(process.exitCode.state, FBFutureStateRunning);
  XCTAssertEqual(process.signal.state, FBFutureStateRunning);

  NSError *error = nil;
  BOOL success = [[process sendSignal:SIGHUP backingOffToKillWithTimeout:0.5 logger:[FBControlCoreLoggerDouble new]] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(process.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(process.exitCode.state, FBFutureStateFailed);
  XCTAssertEqual(process.signal.state, FBFutureStateDone);
  XCTAssertEqual(process.signal.result.intValue, SIGKILL);

  success = [process.statLoc await:&error] != nil;
  XCTAssertEqual(process.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(process.exitCode.state, FBFutureStateFailed);
  XCTAssertEqual(process.signal.state, FBFutureStateDone);
}

- (void)testPipingInputToSuccessivelyRunTasksSucceeds
{
  NSString *tarSource = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.tar.gz", NSUUID.UUID.UUIDString]];
  NSString *tarDestination = [tarSource stringByAppendingString:@".destination"];

  NSError *error = nil;
  BOOL success = [NSFileManager.defaultManager createDirectoryAtPath:tarDestination withIntermediateDirectories:YES attributes:nil error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  success = [[[[[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/tar"]
    withArguments:@[@"-zcvf", tarSource, FBControlCoreFixtures.bundleResource]]
    withStdOutToDevNull]
    withStdErrToDevNull]
    runUntilCompletionWithAcceptableExitCodes:nil]
    mapReplace:NSNull.null]
    await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  NSData *tarData = [NSData dataWithContentsOfFile:tarSource];

  for (NSUInteger count = 0; count < 10; count++) {
    success = [[[[[[[[FBProcessBuilder
      withLaunchPath:@"/usr/bin/tar"]
      withArguments:@[@"-C", tarDestination, @"-zxpf", @"-"]]
      withStdInFromData:tarData]
      withStdOutToDevNull]
      withStdErrToDevNull]
      runUntilCompletionWithAcceptableExitCodes:nil]
      mapReplace:NSNull.null]
      await:&error] != nil;
    XCTAssertNil(error);
    XCTAssertTrue(success);
  }
}

@end
