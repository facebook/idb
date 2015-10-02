/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBTaskExecutor.h>

@interface FBTaskExecutorTests : XCTestCase

@end

@implementation FBTaskExecutorTests

- (void)assertSubstring:(NSString *)needle inString:(NSString *)haystack
{
  XCTAssertNotNil(haystack);
  XCTAssertNotEqual([haystack rangeOfString:needle].location, NSNotFound);
}

- (void)testInMemory
{
  NSString *stdOut = [[[[[[FBTaskExecutor.sharedInstance
    withLaunchPath:@"/usr/bin/man"]
    withArguments:@[@"file"]]
    withWritingInMemory]
    build]
    startSynchronouslyWithTimeout:20]
    stdOut];

  [self assertSubstring:@"determine file type" inString:stdOut];
}

- (void)testBackedByFile
{
  NSString *stdOutPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"testBackedByFile_stdout"] stringByAppendingPathExtension:@"txt"];
  NSString *stdErrPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"testBackedByFile_stderr"] stringByAppendingPathExtension:@"txt"];

  id<FBTask> task = [[[[[FBTaskExecutor.sharedInstance
    withLaunchPath:@"/usr/bin/man"]
    withArguments:@[@"file"]]
    withStdOutPath:stdOutPath stdErrPath:stdErrPath]
    build]
    startSynchronouslyWithTimeout:20];

  NSString *stdOutFileContents = [NSString stringWithContentsOfFile:stdOutPath usedEncoding:nil error:nil];
  [self assertSubstring:@"determine file type" inString:stdOutFileContents];
  [self assertSubstring:@"determine file type" inString:task.stdOut];
}

- (void)testEnvironmentAdditions
{
  NSString *stdOut = [[[[[[[FBTaskExecutor.sharedInstance
    withLaunchPath:@"/usr/bin/env"]
    withArguments:@[]]
    withEnvironmentAdditions:@{@"FOO" : @"BAR"}]
    withWritingInMemory]
    build]
    startSynchronouslyWithTimeout:20]
    stdOut];


  [self assertSubstring:@"FOO=BAR" inString:stdOut];
}

@end
