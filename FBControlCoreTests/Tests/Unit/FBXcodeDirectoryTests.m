/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBXcodeDirectoryTests : XCTestCase

@end

@implementation FBXcodeDirectoryTests

- (void)testXcodeSelect
{
  NSError *error = nil;
  NSString *directory = [FBXcodeDirectory.xcodeSelectDeveloperDirectory await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(directory);
  
  [self assertDirectory:directory];
}

- (void)testFromSymlink
{
  NSError *error = nil;
  NSString *directory = [FBXcodeDirectory symlinkedDeveloperDirectoryWithError:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(directory);
  
  [self assertDirectory:directory];
}
  
- (void)assertDirectory:(NSString *)directory
{
  NSError *error = nil;
  BOOL isDirectory = NO;
  BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&isDirectory];
  XCTAssertTrue(exists);
  XCTAssertTrue(isDirectory);
  
  NSSet<NSString *> *expectedContents = [NSSet setWithArray:@[@"Applications", @"Platforms"]];
  NSArray<NSString *> *actualContents = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:&error];
  NSMutableSet<NSString *> *intersection = [NSMutableSet setWithArray:actualContents];
  [intersection intersectSet:expectedContents];
  
  XCTAssertEqualObjects([intersection copy], expectedContents);
}

@end
