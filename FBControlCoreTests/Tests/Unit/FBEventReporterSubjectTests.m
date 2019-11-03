/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>
#import <FBControlCore/FBControlCore.h>
#import <asl.h>

@interface FBEventReporterSubjectTests : XCTestCase

@end

@implementation FBEventReporterSubjectTests

- (void)checkJsonFields:(id)json name:(FBEventName)name type:(FBEventType)type
{
  XCTAssertEqualObjects(json[FBJSONKeyEventName], name, @"Event name not set correctly: %@ =/= %@", json[FBJSONKeyEventName], name);
  XCTAssertEqualObjects(json[FBJSONKeyEventType], type, @"Event type not set correctly: %@ =/= %@", json[FBJSONKeyEventType], type);
  XCTAssertTrue([json[FBJSONKeyTimestamp] isKindOfClass:[NSNumber class]], @"Date not encoded correctly");
}

- (void)testSimpleSubject
{
  id<FBEventReporterSubject> stringSubject = [FBEventReporterSubject subjectWithString:@"foo"];
  id<FBEventReporterSubject> subject = [FBEventReporterSubject subjectWithName:FBEventNameTap type:FBEventTypeStarted subject:stringSubject];

  NSDictionary *json = subject.jsonSerializableRepresentation;

  [self checkJsonFields:json name:FBEventNameTap type:FBEventTypeStarted];
  XCTAssertEqualObjects(
    json[FBJSONKeySubject], stringSubject.jsonSerializableRepresentation,
    @"Subject text incorrect: %@ =/= %@", json[FBJSONKeySubject], stringSubject.jsonSerializableRepresentation
  );
  XCTAssertEqual(subject.subSubjects.count, 1u);
}

- (void)testControlCoreValueSubject
{
  id<FBEventReporterSubject> stringSubject = [FBEventReporterSubject subjectWithString:@"foo"];
  id<FBEventReporterSubject> subject = [FBEventReporterSubject subjectWithControlCoreValue:stringSubject];

  XCTAssertEqualObjects(
    subject.jsonSerializableRepresentation, stringSubject.jsonSerializableRepresentation,
    @"FBControlCoreSubject producing incorrect json: %@ =/= %@",
    subject.jsonSerializableRepresentation, stringSubject.jsonSerializableRepresentation
  );
  XCTAssertEqual(subject.subSubjects.count, 1u);
}

- (void)testLogSubject
{
  id<FBEventReporterSubject> subject = [FBEventReporterSubject logSubjectWithString:@"log" level:ASL_LEVEL_DEBUG];

  NSDictionary *json = subject.jsonSerializableRepresentation;

  [self checkJsonFields:json name:FBEventNameLog type:FBEventTypeDiscrete];

  XCTAssertEqualObjects(json[FBJSONKeySubject], @"log", @"Log text not set correctly: %@ =/= %@",
    json[FBJSONKeySubject], @"log"
  );
  XCTAssertEqualObjects(json[FBJSONKeyLevel], @"debug", @"Log level text not set correctly: %@ =/= %@",
    json[FBJSONKeyLevel], @"debug"
  );
  XCTAssertEqual(subject.subSubjects.count, 1u);
}

- (void)testCompositeSubject
{
  NSArray<id<FBEventReporterSubject>> *items = @[
    [FBEventReporterSubject subjectWithString:@"foo"],
    [FBEventReporterSubject subjectWithString:@"bar"],
  ];
  id<FBEventReporterSubject> composite = [FBEventReporterSubject compositeSubjectWithArray:items];

  NSArray *json = composite.jsonSerializableRepresentation;

  for (unsigned int i = 0; i < items.count; i++) {
    XCTAssertEqualObjects(json[i], items[i].jsonSerializableRepresentation,
      @"Incorrect item: %@ =/= %@",
      json[i], items[i].jsonSerializableRepresentation
    );
  }
  XCTAssertEqual(composite.subSubjects.count, 2u);
}

- (void)testStringSubject
{
  id<FBEventReporterSubject> subject = [FBEventReporterSubject subjectWithString:@"foo"];

  NSString *json = subject.jsonSerializableRepresentation;

  XCTAssertEqualObjects(json, @"foo", @"JSON isn't just the string contained: %@ =/= foo", json);
  XCTAssertEqual(subject.subSubjects.count, 1u);
}

- (void)testStrings
{
  id<FBEventReporterSubject> subject = [FBEventReporterSubject subjectWithStrings:@[@"foo", @"bar"]];

  NSArray<NSString *> *json = subject.jsonSerializableRepresentation;

  XCTAssertEqualObjects(json, (@[@"foo", @"bar"]), @"JSON isn't just the string contained: %@ =/= foo", json);
  XCTAssertEqual(subject.subSubjects.count, 1u);
}

@end
