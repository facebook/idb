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

  XCTAssertEqual(lines.count, 8u);
  XCTAssertEqualObjects(lines[0], @"0   CoreFoundation                      0x0138ba14 __exceptionPreprocess + 180");
}

@end
