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
    taskWithLaunchPath:@"/usr/bin/base64" arguments:@[@"-i", filePath]]
    startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

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
    taskWithLaunchPath:@"/usr/bin/strings" arguments:@[binaryPath]]
    startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

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
    taskWithLaunchPath:@"/bin/ls" arguments:@[@"-1", resourcesPath]]
    startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

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

  FBTask *task = [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/grep" arguments:@[@"CoreFoundation", filePath]]
    withStdOutLineReader:^(NSString *line) {
      [lines addObject:line];
    }]
    build]
    startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

  XCTAssertTrue(task.hasTerminated);
  XCTAssertNil(task.error);
  XCTAssertGreaterThan(task.processIdentifier, 1);

  XCTAssertEqual(lines.count, 8u);
  XCTAssertEqualObjects(lines[0], @"0   CoreFoundation                      0x0138ba14 __exceptionPreprocess + 180");
}

- (void)testLoggerKeepsOutput
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];

  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/file" arguments:@[bundlePath]]
    withStdErrToLogger:[FBControlCoreLoggerDouble new]]
    withStdOutToLogger:[FBControlCoreLoggerDouble new]]
    build]
    startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

  XCTAssertNil(task.error);
  XCTAssertTrue([task.stdOut containsString:@"directory"]);
}

- (void)testUpdatesStateWithAsynchronousTermination
{
  FBTask *task = [[[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1"]]
    build]
    startAsynchronously];

  BOOL didUpdateTerminationState = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilTrue:^ BOOL {
    return task.hasTerminated;
  }];
  XCTAssertTrue(didUpdateTerminationState);
}

- (void)testAwaitingTerminationOfShortLivedProcess
{
  FBTask *task = [[[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"0"]]
    build]
    startAsynchronously];

  XCTAssertTrue([task waitForCompletionWithTimeout:1 error:nil]);
  XCTAssertTrue(task.hasTerminated);
  XCTAssertTrue(task.wasSuccessful);
  XCTAssertNil(task.error);
}

- (void)testCallsHandlerWithAsynchronousTermination
{
  __block BOOL didCallTerminationHandler = NO;
  [[[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1"]]
    build]
    startAsynchronouslyWithTerminationHandler:^(FBTask *_) {
      didCallTerminationHandler = YES;
    }];

  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilTrue:^ BOOL {
    return didCallTerminationHandler;
  }];
  XCTAssertTrue(didCallTerminationHandler);
}

- (void)testAwaitingTerminationDoesNotTerminateStalledTask
{
  __block BOOL didCallTerminationHandler = NO;
  FBTask *task = [[[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000"]]
    build]
    startAsynchronouslyWithTerminationHandler:^(FBTask *_) {
      didCallTerminationHandler = YES;
    }];

  NSError *error = nil;
  BOOL waitSuccess = [task waitForCompletionWithTimeout:2 error:&error];
  XCTAssertFalse(waitSuccess);
  XCTAssertNotNil(error);
  XCTAssertFalse(didCallTerminationHandler);
  XCTAssertFalse(task.hasTerminated);

  [task terminate];
  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilTrue:^ BOOL {
    return didCallTerminationHandler;
  }];
  XCTAssertTrue(didCallTerminationHandler);
  XCTAssertTrue(task.hasTerminated);
}

- (void)testWaitingSynchronouslyDoesTerminateStalledTask
{
  FBTask *task = [[[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000"]]
    build]
    startSynchronouslyWithTimeout:1];
  XCTAssertTrue(task.hasTerminated);
  XCTAssertNotNil(task.error);
}

@end
