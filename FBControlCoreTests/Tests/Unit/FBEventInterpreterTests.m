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

@interface FBControlCoreValueDouble : NSObject <FBJSONSerializable>

@end

@implementation FBControlCoreValueDouble

- (id)jsonSerializableRepresentation
{
  return @{@"foo": @"bar"};
}

@end

@interface FBEventInterpreterTests : XCTestCase
@end

@implementation FBEventInterpreterTests

- (void)assertSubject:(FBEventReporterSubject *)subject hasJSONContents:(NSArray<NSDictionary<NSString *, id> *> *)contents
{
  id<FBEventInterpreter> interpreter = [FBEventInterpreter jsonEventInterpreter:NO];
  NSArray<NSString *> *lines = [[interpreter interpret:subject] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  for (NSUInteger index = 0; index < contents.count; index++) {
    NSDictionary<NSString *, id> *actual = [NSJSONSerialization JSONObjectWithData:[lines[index] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSDictionary<NSString *, id> *expected = contents[index];
    for (NSString *key in expected.allKeys) {
      XCTAssertEqualObjects(expected[key], actual[key]);
    }
  }
}

- (void)testJSONEventInterpreterOneByOne
{
  FBControlCoreSubject *subject = [[FBControlCoreSubject alloc] initWithValue:FBControlCoreValueDouble.new];
  NSArray<FBEventReporterSubject *> *subjects = @[
    [[FBSimpleSubject alloc] initWithName:FBEventNameLaunch type:FBEventTypeStarted subject:subject],
    [[FBSimpleSubject alloc] initWithName:FBEventNameLaunch type:FBEventTypeEnded subject:subject],
    [[FBSimpleSubject alloc] initWithName:FBEventNameLaunch type:FBEventTypeDiscrete subject:subject],
  ];
  NSArray<NSDictionary<NSString *, id> *> *contents = @[
    @{@"event_type": @"started", @"event_name": @"launch"},
    @{@"event_type": @"ended", @"event_name": @"launch"},
    @{@"event_type": @"discrete", @"event_name": @"launch"},
  ];
  for (NSUInteger index = 0; index < contents.count; index++) {
    NSDictionary<NSString *, id> *expected = contents[index];
    [self assertSubject:subjects[index] hasJSONContents:@[expected]];
  }
}

- (void)testJSONEventInterpreterWithCompositeItem
{
  FBControlCoreSubject *subject = [[FBControlCoreSubject alloc] initWithValue:FBControlCoreValueDouble.new];
  NSArray<FBEventReporterSubject *> *subSubjects = @[
    [[FBSimpleSubject alloc] initWithName:FBEventNameLaunch type:FBEventTypeStarted subject:subject],
    [[FBSimpleSubject alloc] initWithName:FBEventNameLaunch type:FBEventTypeEnded subject:subject],
    [[FBSimpleSubject alloc] initWithName:FBEventNameLaunch type:FBEventTypeDiscrete subject:subject],
  ];
  FBCompositeSubject *compositeSubject = [[FBCompositeSubject alloc] initWithArray:subSubjects];
  [self assertSubject:compositeSubject hasJSONContents:@[
    @{@"event_type": @"started", @"event_name": @"launch"},
    @{@"event_type": @"ended", @"event_name": @"launch"},
    @{@"event_type": @"discrete", @"event_name": @"launch"},
  ]];
}

@end
