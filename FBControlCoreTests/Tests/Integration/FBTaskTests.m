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

@interface FBTaskTests : XCTestCase

@end

@implementation FBTaskTests

- (void)testBase64Matches
{
  NSString *filePath = FBControlCoreFixtures.assetsdCrashPathWithCustomDeviceSet;
  NSString *expected = [[NSData dataWithContentsOfFile:filePath] base64EncodedStringWithOptions:0];

  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/usr/bin/base64" arguments:@[@"-i", filePath]]
    runSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

  XCTAssertTrue(task.hasTerminated);
  XCTAssertNil(task.error);
  XCTAssertEqualObjects(task.stdOut, expected);
  XCTAssertGreaterThan(task.processIdentifier, 1);
}

- (void)testStringsOfCurrentBinary
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];
  NSString *binaryName = [[bundlePath lastPathComponent] stringByDeletingPathExtension];
  NSString *binaryPath = [[bundlePath stringByAppendingPathComponent:@"Contents/MacOS"] stringByAppendingPathComponent:binaryName];

  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/usr/bin/strings" arguments:@[binaryPath]]
    runSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

  XCTAssertTrue(task.hasTerminated);
  XCTAssertNil(task.error);
  XCTAssertTrue([task.stdOut containsString:NSStringFromSelector(_cmd)]);
  XCTAssertGreaterThan(task.processIdentifier, 1);
}

- (void)testBundleContents
{
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  NSString *resourcesPath = [[bundle bundlePath] stringByAppendingPathComponent:@"Contents/Resources"];

  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/ls" arguments:@[@"-1", resourcesPath]]
    runSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

  XCTAssertTrue(task.hasTerminated);
  XCTAssertNil(task.error);
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

  FBTask *task = [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/grep" arguments:@[@"CoreFoundation", filePath]]
    withStdOutLineReader:^(NSString *line) {
      [lines addObject:line];
    }]
    runSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

  XCTAssertTrue([task.stdOut conformsToProtocol:@protocol(FBFileConsumer)]);
  XCTAssertTrue(task.hasTerminated);
  XCTAssertNil(task.error);
  XCTAssertGreaterThan(task.processIdentifier, 1);

  XCTAssertEqual(lines.count, 8u);
  XCTAssertEqualObjects(lines[0], @"0   CoreFoundation                      0x0138ba14 __exceptionPreprocess + 180");
}

- (void)testLogger
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];

  FBTask *task = [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/file" arguments:@[bundlePath]]
    withStdErrToLogger:[FBControlCoreLoggerDouble new]]
    withStdOutToLogger:[FBControlCoreLoggerDouble new]]
    runSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

  XCTAssertNil(task.error);
  XCTAssertTrue([task.stdOut isKindOfClass:FBControlCoreLoggerDouble.class]);
  XCTAssertTrue([task.stdErr isKindOfClass:FBControlCoreLoggerDouble.class]);
}

- (void)testDevNull
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];

  FBTask *task = [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/file" arguments:@[bundlePath]]
    withStdOutToDevNull]
    withStdErrToDevNull]
    runSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

  XCTAssertNil(task.error);
  XCTAssertNil(task.stdOut);
  XCTAssertNil(task.stdErr);
}

- (void)testUpdatesStateWithAsynchronousTermination
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1"]]
    run];

  XCTestExpectation *expectation = [self keyValueObservingExpectationForObject:task keyPath:@"completedTeardown" expectedValue:@YES];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testAwaitingTerminationOfShortLivedProcess
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"0"]]
    run];

  XCTAssertNotNil([task.completed awaitWithTimeout:1 error:nil]);
  XCTAssertTrue(task.hasTerminated);
  XCTAssertTrue(task.wasSuccessful);
  XCTAssertNil(task.error);
}

- (void)testCallsHandlerWithAsynchronousTermination
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Termination Handler Called"];
  [[[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1"]]
    runFuture]
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
    run];

  [task.completed onQueue:dispatch_get_main_queue() notifyOfCompletion:^(id _) {
    [expectation fulfill];
  }];

  NSError *error = nil;
  BOOL waitSuccess = [task.completed awaitWithTimeout:2 error:&error] != nil;
  XCTAssertFalse(waitSuccess);
  XCTAssertNotNil(error);
  XCTAssertFalse(task.hasTerminated);

  [self waitForExpectations:@[expectation] timeout:2];
}

- (void)testWaitingSynchronouslyDoesTerminateStalledTask
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000"]]
    runSynchronouslyWithTimeout:1];
  XCTAssertTrue(task.hasTerminated);
  XCTAssertNotNil(task.error);
}

- (void)testInputReading
{
  NSData *expected = [@"FOO BAR BAZ" dataUsingEncoding:NSUTF8StringEncoding];

  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:@"/bin/cat" arguments:@[]]
    withStdInConnected]
    withStdOutInMemoryAsData]
    withStdErrToDevNull]
    run];

  XCTAssertTrue([task.stdIn conformsToProtocol:@protocol(FBFileConsumer)]);
  [task.stdIn consumeData:expected];
  [task.stdIn consumeEndOfFile];

  NSError *error = nil;
  BOOL waitSuccess = [task.completed awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);

  XCTAssertEqualObjects(expected, task.stdOut);
}

@end
