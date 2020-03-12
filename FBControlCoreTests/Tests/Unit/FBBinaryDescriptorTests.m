/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBBinaryDescriptorTests : XCTestCase

@end

@implementation FBBinaryDescriptorTests

- (void)testFatBinary
{
  // xctest is a fat binary.
  NSError *error = nil;
  FBBinaryDescriptor *descriptor = [FBBinaryDescriptor binaryWithPath:NSProcessInfo.processInfo.arguments.firstObject error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(descriptor);
  XCTAssertNotNil(descriptor.uuid);

  NSArray<NSString *> *rpaths = [descriptor rpathsWithError:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(rpaths);
}

- (void)test64BitMacosCommand
{
  // codesign is not a fat binary.
  NSError *error = nil;
  FBBinaryDescriptor *descriptor = [FBBinaryDescriptor binaryWithPath:@"/usr/bin/codesign" error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(descriptor);
  XCTAssertNotNil(descriptor.uuid);
}

@end
