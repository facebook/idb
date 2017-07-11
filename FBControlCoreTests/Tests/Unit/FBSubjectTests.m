/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>
#import <FBControlCore/FBSubject.h>
#import <asl.h>

@interface FBSubjectTests : XCTestCase

@end

@implementation FBSubjectTests

- (void)testFBEventReporterSubject
{
  FBEventReporterSubject *subject = [[FBEventReporterSubject alloc] init];

  XCTAssertTrue([subject.subSubjects containsObject:subject], @"Every FBEventReporterSubject should have itself as a subsubject");
}

- (void)testFBSimpleSubject
{
  FBStringSubject *stringSubject = [[FBStringSubject alloc] initWithString:@"foo"];

  FBSimpleSubject *subject = [[FBSimpleSubject alloc] initWithName:FBEventNameTap
                                                              type:FBEventTypeStarted
                                                           subject:stringSubject];

  NSDictionary *json = subject.jsonSerializableRepresentation;

  [self checkJsonFields:json name:FBEventNameTap type:FBEventTypeStarted];
  XCTAssertEqualObjects(
    json[FBJSONKeySubject], stringSubject.jsonSerializableRepresentation,
    @"Subject text incorrect: %@ =/= %@", json[FBJSONKeySubject], stringSubject.jsonSerializableRepresentation
  );
}

- (void)checkJsonFields:(id)json name:(FBEventName)name type:(FBEventType)type
{
  XCTAssertEqualObjects(json[FBJSONKeyEventName], name, @"Event name not set correctly: %@ =/= %@", json[FBJSONKeyEventName], name);
  XCTAssertEqualObjects(json[FBJSONKeyEventType], type, @"Event type not set correctly: %@ =/= %@", json[FBJSONKeyEventType], type);
  XCTAssertTrue([json[FBJSONKeyTimestamp] isKindOfClass:[NSNumber class]], @"Date not encoded correctly");
}

- (void)testFBControlCoreSubject
{
  FBStringSubject *stringSubject = [[FBStringSubject alloc] initWithString:@"foo"];
  FBControlCoreSubject *subject = [[FBControlCoreSubject alloc] initWithValue:stringSubject];

  XCTAssertEqualObjects(
    subject.jsonSerializableRepresentation, stringSubject.jsonSerializableRepresentation,
    @"FBControlCoreSubject producing incorrect json: %@ =/= %@",
    subject.jsonSerializableRepresentation, stringSubject.jsonSerializableRepresentation
  );
}

- (void)FBLogSubject
{
  FBLogSubject *subject = [[FBLogSubject alloc] initWithLogString:@"log"
                                                            level:ASL_LEVEL_DEBUG];

  NSDictionary *json = subject.jsonSerializableRepresentation;

  [self checkJsonFields:json name:FBEventNameLog type:FBEventTypeDiscrete];

  XCTAssertEqualObjects(json[FBJSONKeySubject], @"log", @"Log text not set correctly: %@ =/= %@",
    json[FBJSONKeySubject], @"log"
  );
  XCTAssertEqualObjects(json[FBJSONKeyLevel], @"debug", @"Log level text not set correctly: %@ =/= %@",
    json[FBJSONKeyLevel], @"debug"
  );
}

- (void)testFBCompositeSubject
{
  NSArray<FBStringSubject *> *items = @[
    [[FBStringSubject alloc] initWithString:@"foo"],
    [[FBStringSubject alloc] initWithString:@"bar"],
  ];

  FBCompositeSubject *composite = [[FBCompositeSubject alloc] initWithArray:items];

  NSArray *json = composite.jsonSerializableRepresentation;

  for (unsigned int i = 0; i < items.count; i++) {
    XCTAssertEqualObjects(json[i], items[i].jsonSerializableRepresentation,
      @"Incorrect item: %@ =/= %@",
      json[i], items[i].jsonSerializableRepresentation
    );
  }
}

- (void)testFBRecordSubject
{
  FBRecordSubject *subject = [[FBRecordSubject alloc] initWithState:YES path:@"p"];

  NSDictionary *json = subject.jsonSerializableRepresentation;

  XCTAssertTrue([json[@"start"] boolValue], @"Started value incorrect: %c =/= YES", [json[@"start"] boolValue]);
  XCTAssertEqualObjects(json[@"path"], @"p", @"Path value incorrect: %@ =/= p", json[@"path"]);
}

- (void)testFBStringSubject
{
  FBStringSubject *subject = [[FBStringSubject alloc] initWithString:@"foo"];

  NSString *json = subject.jsonSerializableRepresentation;

  XCTAssertEqualObjects(json, @"foo", @"JSON isn't just the string contained: %@ =/= foo", json);
}

- (void)testFBBoolSubject
{
  FBBoolSubject *subject = [[FBBoolSubject alloc] initWithBool:YES];

  id json = subject.jsonSerializableRepresentation;

  XCTAssertTrue([json isKindOfClass:[NSNumber class]], @"Should return an NSNumber");
  XCTAssertNotEqual([json intValue], 0, @"Incorrect value");
}

@end
