/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "XCTestCase+FBXCTestKitTests.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <FBXCTestKit/FBXCTestKit.h>

@implementation XCTestCase (Test)

- (FBXCTestLogger *)logger
{
  NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  BOOL success = [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
  XCTAssertTrue(success);
  return [FBXCTestLogger defaultLoggerInDirectory:directory];
}

+ (BOOL)isRunningOnTravis
{
  if (NSProcessInfo.processInfo.environment[@"TRAVIS"]) {
    NSLog(@"Running in Travis environment, skipping test");
    return YES;
  }
  return NO;
}

@end
