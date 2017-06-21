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

#import "FBControlCoreValueTestCase.h"
#import "FBiOSTargetDouble.h"

@interface FBUploadBufferTests : FBControlCoreValueTestCase

@end

@implementation FBUploadBufferTests

+ (NSArray<FBUploadHeader *> *)headers
{
  return @[
    [FBUploadHeader headerWithPathExtension:@"bin" size:10],
    [FBUploadHeader headerWithPathExtension:@"foo" size:1024],
  ];
}

+ (NSArray<FBUploadedDestination *> *)uploads
{
  return @[
    [FBUploadedDestination destinationWithHeader:[FBUploadHeader headerWithPathExtension:@"foo" size:10] path:@"/some.foo"],
    [FBUploadedDestination destinationWithHeader:[FBUploadHeader headerWithPathExtension:@"bar" size:1024] path:@"/other/some.bar"],
  ];
}

+ (FBUploadBuffer *)buffer
{
  return [FBUploadBuffer bufferWithHeader:[FBUploadHeader headerWithPathExtension:@"txt" size:11] workingDirectory:NSTemporaryDirectory()];
}

- (void)testValueSemanticsOfHeader
{
  NSArray<FBUploadHeader *> *headers = FBUploadBufferTests.headers;
  [self assertEqualityOfCopy:headers];
  [self assertJSONSerialization:headers];
  [self assertJSONDeserialization:headers];
}

- (void)testValueSemanticsOfUploaded
{
  NSArray<FBUploadedDestination *> *uploads = FBUploadBufferTests.uploads;
  [self assertEqualityOfCopy:uploads];
  [self assertJSONSerialization:uploads];
  [self assertJSONDeserialization:uploads];
}

- (void)testOneShotSplitsAndReturnsRemainderOfBuffer
{
  NSData *input = [@"Binary DataSome Other Data" dataUsingEncoding:NSUTF8StringEncoding];
  FBUploadBuffer *buffer = FBUploadBufferTests.buffer;
  NSData *remainder = nil;
  FBUploadedDestination *output = [buffer writeData:input remainderOut:&remainder];

  NSData *expected = [@"Binary Data" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(output.data, expected);

  expected = [@"Some Other Data" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(remainder, expected);
}

- (void)testTwoShotSplitsAndReturnsRemainderOfBuffer
{
  NSData *input = [@"Binary Data" dataUsingEncoding:NSUTF8StringEncoding];
  FBUploadBuffer *buffer = FBUploadBufferTests.buffer;
  NSData *remainder = nil;
  FBUploadedDestination *output = [buffer writeData:input remainderOut:&remainder];

  NSData *expected = [@"Binary Data" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(output.data, expected);
  XCTAssertNil(remainder);

  input = [@"Some Other Data" dataUsingEncoding:NSUTF8StringEncoding];
  output = [buffer writeData:input remainderOut:&remainder];
  expected = [@"Some Other Data" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(remainder, expected);
}

- (void)testTwoShotSparseSplitsAndReturnsRemainderOfBuffer
{
  NSData *input = [@"Binary Da" dataUsingEncoding:NSUTF8StringEncoding];
  FBUploadBuffer *buffer = FBUploadBufferTests.buffer;
  NSData *remainder = nil;
  FBUploadedDestination *output = [buffer writeData:input remainderOut:&remainder];

  XCTAssertNil(output);
  XCTAssertNil(remainder);

  input = [@"taSome Other Data" dataUsingEncoding:NSUTF8StringEncoding];
  output = [buffer writeData:input remainderOut:&remainder];
  NSData *expected = [@"Binary Data" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(output.data, expected);
  expected = [@"Some Other Data" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(remainder, expected);

  input = [@"But wait there's more" dataUsingEncoding:NSUTF8StringEncoding];
  output = [buffer writeData:input remainderOut:&remainder];
  expected = [@"Binary Data" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(output.data, expected);
  expected = [@"But wait there's more" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(remainder, expected);
}

@end
