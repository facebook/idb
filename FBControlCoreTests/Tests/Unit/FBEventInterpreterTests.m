/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>
#import <FBControlCore/FBEventInterpreter.h>
#import <FBControlCore/FBSubject.h>

@interface FBTestInterpreter : FBBaseEventInterpreter
@end


@implementation FBTestInterpreter

- (NSString *)getStringFromEventReporterSubject:(FBEventReporterSubject *)subject
{
  return subject.description;
}

@end


@interface FBEventInterpreterTests : XCTestCase
@end

@implementation FBEventInterpreterTests

- (void)testFBBaseEventInterpreterWithArray
{
  FBBaseEventInterpreter *interpreter = [[FBTestInterpreter alloc] init];

  NSArray<FBEventReporterSubject *> *subSubjects = @[
    [[FBStringSubject alloc] initWithString:@"foo"],
    [[FBStringSubject alloc] initWithString:@"bar"],
    [[FBStringSubject alloc] initWithString:@"zar"],
  ];

  FBCompositeSubject *subject = [[FBCompositeSubject alloc] initWithArray:subSubjects];

  NSArray<NSString *> *strings = [interpreter interpret:subject];

  NSUInteger expectedCount = subSubjects.count;
  NSUInteger actualCount = strings.count;
  XCTAssertEqual(expectedCount, actualCount, @"Should return %lu results, not %lu", expectedCount, actualCount);

  for (unsigned int i = 0; i < subSubjects.count; i++) {
    FBEventReporterSubject *subsubject = subSubjects[i];

    NSString *actual = strings[i];
    NSString *expected = subsubject.description;
    XCTAssertEqualObjects(actual, expected, @"Interpreted result incorrect: %@ =/= %@", actual, expected);
  }
}

- (void)testFBBaseEventInterpreterWithSingleItem
{
  FBBaseEventInterpreter *interpreter = [[FBTestInterpreter alloc] init];

  FBStringSubject *subject = [[FBStringSubject alloc] initWithString:@"foo"];

  NSArray<NSString *> *strings = [interpreter interpret:subject];

  XCTAssertEqual(strings.count, (unsigned long)1, @"Should return only one result, not %lu", strings.count);

  NSString *actual = strings[0];
  NSString *expected = subject.description;
  XCTAssertEqualObjects(actual, expected, @"Interpreted result incorrect: %@ =/= %@", actual, expected);
}

@end
