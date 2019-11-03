/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

- (NSString *)description
{
  return @"Foo | Bar";
}

@end

@interface FBEventInterpreterTests : XCTestCase
@end

@implementation FBEventInterpreterTests

- (void)assertSubject:(id<FBEventReporterSubject>)subject hasJSONContents:(NSArray<NSDictionary<NSString *, id> *> *)contents
{
  id<FBEventInterpreter> interpreter = [FBEventInterpreter jsonEventInterpreter:NO];
  NSArray<NSString *> *lines = [[interpreter interpret:subject] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  XCTAssertEqualObjects(lines.lastObject, @"");
  XCTAssertEqual(contents.count, lines.count - 1);

  for (NSUInteger index = 0; index < contents.count; index++) {
    NSDictionary<NSString *, id> *actual = [NSJSONSerialization JSONObjectWithData:[lines[index] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSDictionary<NSString *, id> *expected = contents[index];

    XCTAssertTrue([FBCollectionInformation isDictionaryHeterogeneous:actual keyClass:NSString.class valueClass:NSObject.class]);
    XCTAssertTrue([FBCollectionInformation isDictionaryHeterogeneous:expected keyClass:NSString.class valueClass:NSObject.class]);
    for (NSString *key in expected.allKeys) {
      XCTAssertEqualObjects(expected[key], actual[key]);
    }
  }
}

- (void)assertSubject:(id<FBEventReporterSubject>)subject hasHumanReadableContents:(NSArray<NSString *> *)contents
{
  id<FBEventInterpreter> interpreter = [FBEventInterpreter humanReadableInterpreter];
  NSArray<NSString *> *lines = [[interpreter interpret:subject] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  XCTAssertEqualObjects(lines.lastObject, @"");
  XCTAssertEqual(contents.count, lines.count - 1);

  for (NSUInteger index = 0; index < contents.count; index++) {
    NSString *actual = lines[index];
    NSString *expected = contents[index];
    XCTAssertEqualObjects(actual, expected);
  }
}

- (void)testEventInterpretersOneByOne
{
  id<FBEventReporterSubject> baseSubject = [FBEventReporterSubject subjectWithControlCoreValue:FBControlCoreValueDouble.new];
  NSArray<id<FBEventReporterSubject>> *subjects = @[
    [FBEventReporterSubject subjectWithName:FBEventNameLaunch type:FBEventTypeStarted subject:baseSubject],
    [FBEventReporterSubject subjectWithName:FBEventNameLaunch type:FBEventTypeEnded subject:baseSubject],
    [FBEventReporterSubject subjectWithName:FBEventNameLaunch type:FBEventTypeDiscrete subject:baseSubject],
  ];
  NSArray<NSDictionary<NSString *, id> *> *jsonContents = @[
    @{@"event_type": @"started", @"event_name": @"launch"},
    @{@"event_type": @"ended", @"event_name": @"launch"},
    @{@"event_type": @"discrete", @"event_name": @"launch"},
  ];
  NSArray<NSString *> *humanReadableContents = @[
    @"launch started: Foo | Bar",
    @"launch ended: Foo | Bar",
    @"Foo | Bar",
  ];
  for (NSUInteger index = 0; index < subjects.count; index++) {
    id<FBEventReporterSubject> subject = subjects[index];
    NSArray<NSDictionary<NSString *, id> *> *expectedJSON = @[jsonContents[index]];
    NSArray<NSString *> *expectedHumanReadable = @[humanReadableContents[index]];
    [self assertSubject:subject hasJSONContents:expectedJSON];
    [self assertSubject:subject hasHumanReadableContents:expectedHumanReadable];
  }
}

- (void)testDiscreteSingleItemWithCompositeValue
{
  NSArray<id<FBEventReporterSubject>> *subjects = @[
    [FBEventReporterSubject subjectWithControlCoreValue:FBControlCoreValueDouble.new],
    [FBEventReporterSubject subjectWithControlCoreValue:FBControlCoreValueDouble.new],
    [FBEventReporterSubject subjectWithControlCoreValue:FBControlCoreValueDouble.new],
  ];

  id<FBEventReporterSubject> subject = [FBEventReporterSubject
    subjectWithName:FBEventNameLaunch
    type:FBEventTypeDiscrete
    subject:[FBEventReporterSubject compositeSubjectWithArray:subjects]];
  [self assertSubject:subject hasJSONContents:@[
    @{@"event_type": @"discrete", @"event_name": @"launch", @"subject": @[
      @{@"foo": @"bar"},
      @{@"foo": @"bar"},
      @{@"foo": @"bar"}
    ]},
  ]];
  [self assertSubject:subject hasHumanReadableContents:@[
    @"Foo | Bar",
    @"Foo | Bar",
    @"Foo | Bar",
  ]];
}

- (void)testEventInterpretersWithCompositeItem
{
  id<FBEventReporterSubject> subject = [FBEventReporterSubject subjectWithControlCoreValue:FBControlCoreValueDouble.new];
  NSArray<id<FBEventReporterSubject>> *subSubjects = @[
    [FBEventReporterSubject subjectWithName:FBEventNameLaunch type:FBEventTypeStarted subject:subject],
    [FBEventReporterSubject subjectWithName:FBEventNameLaunch type:FBEventTypeEnded subject:subject],
    [FBEventReporterSubject subjectWithName:FBEventNameLaunch type:FBEventTypeDiscrete subject:subject],
  ];
  id<FBEventReporterSubject> compositeSubject = [FBEventReporterSubject compositeSubjectWithArray:subSubjects];
  [self assertSubject:compositeSubject hasJSONContents:@[
    @{@"event_type": @"started", @"event_name": @"launch"},
    @{@"event_type": @"ended", @"event_name": @"launch"},
    @{@"event_type": @"discrete", @"event_name": @"launch"},
  ]];
  [self assertSubject:compositeSubject hasHumanReadableContents:@[
    @"launch started: Foo | Bar",
    @"launch ended: Foo | Bar",
    @"Foo | Bar",
  ]];
}

- (void)testStringsReporting
{
  id<FBEventReporterSubject> subject = [FBEventReporterSubject
    subjectWithName:FBEventNameLaunch
    type:FBEventTypeDiscrete
    subject:[FBEventReporterSubject subjectWithStrings:@[@"Foo", @"Bar", @"Baz"]]];

  [self assertSubject:subject hasJSONContents:@[@{@"subject": @[@"Foo", @"Bar", @"Baz"] }]];
  [self assertSubject:subject hasHumanReadableContents:@[@"[Foo, Bar, Baz]"]];
}

@end
