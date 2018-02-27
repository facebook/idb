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

@interface FBProcessStreamTests : XCTestCase

@end

@implementation FBProcessStreamTests

- (void)testClosingActiveStreamStopsWriting
{
  FBAccumilatingFileConsumer *consumer = [FBAccumilatingFileConsumer new];

  FBProcessOutput *output = [FBProcessOutput outputForFileConsumer:consumer];
  NSError *error = nil;
  NSPipe *pipe = [[output attachToPipeOrFileHandle] await:&error];
  XCTAssertNil(error);
  XCTAssertTrue([pipe isKindOfClass:NSPipe.class]);

  [pipe.fileHandleForWriting writeData:[@"HELLO WORLD\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [pipe.fileHandleForWriting writeData:[@"HELLO AGAIN"  dataUsingEncoding:NSUTF8StringEncoding]];

  BOOL success = [[output detach] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  XCTAssertThrows(pipe.fileHandleForWriting.fileDescriptor);
  XCTAssertTrue(consumer.eofHasBeenReceived.hasCompleted);
}

@end
