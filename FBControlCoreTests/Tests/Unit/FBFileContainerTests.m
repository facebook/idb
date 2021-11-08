/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBFileContainerTests : XCTestCase

@end

@implementation FBFileContainerTests

- (void)testPathMapping
{
  NSString *fooPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"FBSimulatorFileCommandsTests_testPathMapping_foo"];
  NSString *fileInFoo = [fooPath stringByAppendingPathComponent:@"file.txt"];
  NSString *barPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"FBSimulatorFileCommandsTests_testPathMapping_bar"];
  NSString *directoryInBar = [barPath stringByAppendingPathComponent:@"dir"];
  NSString *fileInDirectoryInBar = [directoryInBar stringByAppendingPathComponent:@"in_dir.txt"];

  NSError *error = nil;
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:fooPath withIntermediateDirectories:YES attributes:nil error:&error]);
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:barPath withIntermediateDirectories:YES attributes:nil error:&error]);
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:directoryInBar withIntermediateDirectories:YES attributes:nil error:&error]);

  NSString *fileInFooText = @"Some Text";
  XCTAssertTrue([fileInFooText writeToFile:fileInFoo atomically:YES encoding:NSUTF8StringEncoding error:&error]);

  NSString *fileInDirectoryInBarText = @"Other Text";
  XCTAssertTrue([fileInDirectoryInBarText writeToFile:fileInDirectoryInBar atomically:YES encoding:NSUTF8StringEncoding error:&error]);

  NSDictionary<NSString *, NSString *> *pathMapping = @{@"foo": fooPath, @"bar": barPath};
  id<FBFileContainer> container = [FBFileContainer fileContainerForPathMapping:pathMapping];

  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"foo", @"bar"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"."] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);

  expectedFiles = [NSSet setWithArray:@[@"file.txt"]];
  actualFiles = [[container contentsOfDirectory:@"foo"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);

  expectedFiles = [NSSet setWithArray:@[@"dir"]];
  actualFiles = [[container contentsOfDirectory:@"bar"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);

  expectedFiles = [NSSet setWithArray:@[@"in_dir.txt"]];
  actualFiles = [[container contentsOfDirectory:@"bar/dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

@end
