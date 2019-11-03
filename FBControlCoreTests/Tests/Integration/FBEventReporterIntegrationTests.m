/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBEventReporterIntegrationTests : XCTestCase

@end

@implementation FBEventReporterIntegrationTests

- (void)recursiveAssertDictionaryMatch:(NSDictionary *)actual expected:(NSDictionary *)expected
{
  for (NSString *key in expected.allKeys) {
    id nextActual = actual[key];
    id nextExpected = expected[key];
    if ([nextActual isKindOfClass:NSDictionary.class]) {
      [self recursiveAssertDictionaryMatch:nextActual expected:nextExpected];
    } else {
      XCTAssertEqualObjects(nextExpected, nextActual);
    }
  }
}

- (void)assertSubject:(id<FBEventReporterSubject>)subject hasJSONContents:(NSArray<NSDictionary<NSString *, id> *> *)contents
{
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBEventInterpreter> interpreter = [FBEventInterpreter jsonEventInterpreter:NO];
  id<FBEventReporter> reporter = [FBEventReporter reporterWithInterpreter:interpreter consumer:consumer];

  [reporter report:subject];
  NSArray<NSString *> *lines = consumer.lines;
  XCTAssertEqualObjects(lines.lastObject, @"");
  XCTAssertEqual(contents.count, lines.count - 1);

  for (NSUInteger index = 0; index < contents.count; index++) {
    NSDictionary<NSString *, id> *actual = [NSJSONSerialization JSONObjectWithData:[lines[index] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSDictionary<NSString *, id> *expected = contents[index];

    XCTAssertTrue([FBCollectionInformation isDictionaryHeterogeneous:actual keyClass:NSString.class valueClass:NSObject.class]);
    XCTAssertTrue([FBCollectionInformation isDictionaryHeterogeneous:expected keyClass:NSString.class valueClass:NSObject.class]);
    [self recursiveAssertDictionaryMatch:actual expected:expected];
  }
}

- (void)testApplicationLaunch
{
  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithBundleID:@"com.foo.bar"
    bundleName:@"FooBar"
    arguments:@[@"bar"]
    environment:@{}
    waitForDebugger:NO
    output:FBProcessOutputConfiguration.outputToDevNull];
  id<FBEventReporterSubject> subject = [FBEventReporterSubject compositeSubjectWithArray:@[
    [FBEventReporterSubject subjectWithName:FBEventNameLaunch type:FBEventTypeStarted value:appLaunch],
    [FBEventReporterSubject subjectWithName:FBEventNameLaunch type:FBEventTypeEnded value:appLaunch],
  ]];

  [self assertSubject:subject hasJSONContents:@[
    @{@"event_name" : @"launch", @"event_type" : @"started", @"subject": @{@"bundle_id" : @"com.foo.bar"}},
    @{@"event_name" : @"launch", @"event_type" : @"ended", @"subject": @{@"bundle_id" : @"com.foo.bar"}},
  ]];
}

- (void)testSettingsApproval
{
  FBSettingsApproval *settingsApproval = [FBSettingsApproval approvalWithBundleIDs:@[@"com.foo.bar", @"bing.bong"] services:@[FBSettingsApprovalServiceContacts]];
  id<FBEventReporterSubject> subject = [FBEventReporterSubject compositeSubjectWithArray:@[
    [FBEventReporterSubject subjectWithName:FBEventNameApprove type:FBEventTypeStarted value:settingsApproval],
    [FBEventReporterSubject subjectWithName:FBEventNameApprove type:FBEventTypeEnded value:settingsApproval],
  ]];

  [self assertSubject:subject hasJSONContents:@[
    @{@"event_name" : @"approve", @"event_type" : @"started", @"subject": @{@"bundle_ids" : @[@"com.foo.bar", @"bing.bong"], @"services": @[@"contacts"]}},
    @{@"event_name" : @"approve", @"event_type" : @"ended", @"subject": @{@"bundle_ids" : @[@"com.foo.bar", @"bing.bong"], @"services": @[@"contacts"]}},
  ]];
}

- (void)testLogTail
{
  FBLogTailConfiguration *logTail = [FBLogTailConfiguration configurationWithArguments:@[@"--again"]];
  id<FBEventReporterSubject> subject = [FBEventReporterSubject compositeSubjectWithArray:@[
    [FBEventReporterSubject subjectWithName:FBEventNameLog type:FBEventTypeStarted value:logTail],
    [FBEventReporterSubject subjectWithName:FBEventNameLog type:FBEventTypeEnded value:logTail],
  ]];

  [self assertSubject:subject hasJSONContents:@[
    @{@"event_name" : @"log", @"event_type" : @"started", @"subject": @{@"arguments" : @[@"--again"]}},
    @{@"event_name" : @"log", @"event_type" : @"ended", @"subject":  @{@"arguments" : @[@"--again"]}},
  ]];
}

@end
