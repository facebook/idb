/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBJSONTestReporterTests : XCTestCase

@property (nonatomic, strong, readwrite) NSMutableArray<NSString *> *lines;
@property (nonatomic, strong, readwrite) id<FBDataConsumer> consumer;
@property (nonatomic, strong, readwrite) FBJSONTestReporter *reporter;

@end

@implementation FBJSONTestReporterTests

- (void)setUp
{
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  self.consumer = [FBBlockDataConsumer synchronousLineConsumerWithBlock:^(NSString *line) {
    [lines addObject:line];
  }];
  self.reporter = [[FBJSONTestReporter alloc] initWithTestBundlePath:@"/path.bundle" testType:@"footype" logger:nil dataConsumer:self.consumer];
  self.lines = lines;
}

- (NSDictionary<NSString *, id> *)objectAtLine:(NSUInteger)index
{
  NSString *line = self.lines[index];
  NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  NSDictionary<NSString *, id> *object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(object);
  return object;
}

- (NSDictionary<NSString *, id> *)objectAtIndexedSubscript:(NSUInteger)index
{
  return [self objectAtLine:index];
}

- (void)testReportsTests
{
  [self.reporter didBeginExecutingTestPlan];
  [self.reporter didFinishExecutingTestPlan];
  NSError *error = nil;
  BOOL success = [self.reporter printReportWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertEqual(self.lines.count, 2u);
  XCTAssertEqualObjects(self[0][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[0][@"event"], @"begin-ocunit");
  XCTAssertEqualObjects(self[1][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[1][@"event"], @"end-ocunit");
  XCTAssertEqualObjects(self[1][@"succeeded"], @1);
}

- (void)testNoStartOfTestPlan
{
  [self.reporter didFinishExecutingTestPlan];
  NSError *error = nil;
  BOOL success = [self.reporter printReportWithError:&error];
  XCTAssertFalse(success);
  XCTAssertNotNil(error);

  XCTAssertEqual(self.lines.count, 2u);
  XCTAssertEqualObjects(self[0][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[0][@"event"], @"begin-ocunit");
  XCTAssertEqualObjects(self[1][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[1][@"event"], @"end-ocunit");
  XCTAssertEqualObjects(self[1][@"succeeded"], @0);
  XCTAssertEqualObjects(self[1][@"message"], @"No didBeginExecutingTestPlan event was received.");
}

- (void)testReportTestSuccess
{
  [self.reporter didBeginExecutingTestPlan];
  [self.reporter testCaseDidStartForTestClass:@"FooTest" method:@"BarCase"];
  [self.reporter testCaseDidFinishForTestClass:@"FooTest" method:@"BarCase" withStatus:FBTestReportStatusPassed duration:1 logs:nil];
  [self.reporter didFinishExecutingTestPlan];
  NSError *error = nil;
  BOOL success = [self.reporter printReportWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertEqual(self.lines.count, 4u);
  XCTAssertEqualObjects(self[0][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[0][@"event"], @"begin-ocunit");

  XCTAssertEqualObjects(self[1][@"className"], @"FooTest");
  XCTAssertEqualObjects(self[1][@"methodName"], @"BarCase");
  XCTAssertEqualObjects(self[1][@"event"], @"begin-test");
  XCTAssertEqualObjects(self[1][@"test"], @"-[FooTest BarCase]");

  XCTAssertEqualObjects(self[2][@"className"], @"FooTest");
  XCTAssertEqualObjects(self[2][@"methodName"], @"BarCase");
  XCTAssertEqualObjects(self[2][@"event"], @"end-test");
  XCTAssertEqualObjects(self[2][@"test"], @"-[FooTest BarCase]");
  XCTAssertEqualObjects(self[2][@"result"], @"success");
  XCTAssertEqualObjects(self[2][@"succeeded"], @1);

  XCTAssertEqualObjects(self[3][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[3][@"event"], @"end-ocunit");
  XCTAssertEqualObjects(self[3][@"succeeded"], @1);
}

- (void)testReportMultipleTestCases
{
  NSDictionary<NSArray<NSString *> *, NSNumber *> *cases = @{
    @[@"FooTest", @"BarCase"] : @(FBTestReportStatusPassed),
    @[@"BazTest", @"CatCase"] : @(FBTestReportStatusFailed),
    @[@"BingTest", @"DogCase"] : @(FBTestReportStatusPassed),
    @[@"BlipTest", @"BagCase"] : @(FBTestReportStatusFailed),
  };

  [self.reporter didBeginExecutingTestPlan];
  for (NSArray<NSString *> *pairs in cases.allKeys) {
    [self.reporter testCaseDidStartForTestClass:pairs[0] method:pairs[1]];
    [self.reporter testCaseDidFinishForTestClass:pairs[0] method:pairs[1] withStatus:cases[pairs].unsignedIntegerValue duration:1 logs:nil];
  }
  [self.reporter didFinishExecutingTestPlan];
  NSError *error = nil;
  BOOL success = [self.reporter printReportWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  NSUInteger count = 2u + (2u * cases.count);
  XCTAssertEqual(self.lines.count, count);
  XCTAssertEqualObjects(self[0][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[0][@"event"], @"begin-ocunit");

  XCTAssertEqualObjects(self[count - 1][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[count - 1][@"event"], @"end-ocunit");
  XCTAssertEqualObjects(self[count - 1][@"succeeded"], @1);
}


- (void)testReportTestFailure
{
  [self.reporter didBeginExecutingTestPlan];
  [self.reporter testCaseDidStartForTestClass:@"FooTest" method:@"BarCase"];
  [self.reporter testCaseDidFailForTestClass:@"FooTest" method:@"BarCase" withMessage:@"BadBar" file:@"BadFile" line:42];
  [self.reporter testCaseDidFinishForTestClass:@"FooTest" method:@"BarCase" withStatus:FBTestReportStatusFailed duration:1 logs:nil];
  [self.reporter didFinishExecutingTestPlan];
  NSError *error = nil;
  BOOL success = [self.reporter printReportWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertEqual(self.lines.count, 4u);
  XCTAssertEqualObjects(self[0][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[0][@"event"], @"begin-ocunit");

  XCTAssertEqualObjects(self[1][@"className"], @"FooTest");
  XCTAssertEqualObjects(self[1][@"methodName"], @"BarCase");
  XCTAssertEqualObjects(self[1][@"event"], @"begin-test");
  XCTAssertEqualObjects(self[1][@"test"], @"-[FooTest BarCase]");

  XCTAssertEqualObjects(self[2][@"className"], @"FooTest");
  XCTAssertEqualObjects(self[2][@"methodName"], @"BarCase");
  XCTAssertEqualObjects(self[2][@"event"], @"end-test");
  XCTAssertEqualObjects(self[2][@"test"], @"-[FooTest BarCase]");
  XCTAssertEqualObjects(self[2][@"result"], @"failure");
  XCTAssertEqualObjects(self[2][@"succeeded"], @0);
  XCTAssertEqualObjects(self[2][@"exceptions"][0][@"reason"], @"BadBar");

  XCTAssertEqualObjects(self[3][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[3][@"event"], @"end-ocunit");
  XCTAssertEqualObjects(self[3][@"succeeded"], @1);
}

- (void)testReportTestOutput
{
  [self.reporter didBeginExecutingTestPlan];
  [self.reporter testCaseDidStartForTestClass:@"FooTest" method:@"BarCase"];
  [self.reporter testHadOutput:@"Some Output For Foo"];
  [self.reporter testCaseDidFinishForTestClass:@"FooTest" method:@"BarCase" withStatus:FBTestReportStatusPassed duration:1 logs:nil];
  [self.reporter didFinishExecutingTestPlan];
  NSError *error = nil;
  BOOL success = [self.reporter printReportWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertEqual(self.lines.count, 5u);
  XCTAssertEqualObjects(self[0][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[0][@"event"], @"begin-ocunit");

  XCTAssertEqualObjects(self[1][@"className"], @"FooTest");
  XCTAssertEqualObjects(self[1][@"methodName"], @"BarCase");
  XCTAssertEqualObjects(self[1][@"event"], @"begin-test");
  XCTAssertEqualObjects(self[1][@"test"], @"-[FooTest BarCase]");

  XCTAssertEqualObjects(self[2][@"event"], @"test-output");
  XCTAssertEqualObjects(self[2][@"output"], @"Some Output For Foo");

  XCTAssertEqualObjects(self[3][@"className"], @"FooTest");
  XCTAssertEqualObjects(self[3][@"methodName"], @"BarCase");
  XCTAssertEqualObjects(self[3][@"event"], @"end-test");
  XCTAssertEqualObjects(self[3][@"test"], @"-[FooTest BarCase]");
  XCTAssertEqualObjects(self[3][@"result"], @"success");
  XCTAssertEqualObjects(self[3][@"succeeded"], @1);

  XCTAssertEqualObjects(self[4][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[4][@"event"], @"end-ocunit");
  XCTAssertEqualObjects(self[4][@"succeeded"], @1);
}

- (void)testBundleCrashIfNoDidFinish
{
  [self.reporter didBeginExecutingTestPlan];
  [self.reporter testCaseDidStartForTestClass:@"FooTest" method:@"BarCase"];
  [self.reporter testCaseDidFinishForTestClass:@"FooTest" method:@"BarCase" withStatus:FBTestReportStatusFailed duration:1 logs:nil];
  NSError *error = nil;
  BOOL success = [self.reporter printReportWithError:&error];
  XCTAssertFalse(success);
  XCTAssertNotNil(error);

  XCTAssertEqual(self.lines.count, 4u);
  XCTAssertEqualObjects(self[0][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[0][@"event"], @"begin-ocunit");

  XCTAssertEqualObjects(self[1][@"className"], @"FooTest");
  XCTAssertEqualObjects(self[1][@"methodName"], @"BarCase");
  XCTAssertEqualObjects(self[1][@"event"], @"begin-test");
  XCTAssertEqualObjects(self[1][@"test"], @"-[FooTest BarCase]");

  XCTAssertEqualObjects(self[2][@"className"], @"FooTest");
  XCTAssertEqualObjects(self[2][@"methodName"], @"BarCase");
  XCTAssertEqualObjects(self[2][@"event"], @"end-test");
  XCTAssertEqualObjects(self[2][@"test"], @"-[FooTest BarCase]");

  XCTAssertEqualObjects(self[3][@"bundleName"], @"path.bundle");
  XCTAssertEqualObjects(self[3][@"message"], @"No didFinishExecutingTestPlan event was received, the test bundle has likely crashed.");
  XCTAssertEqualObjects(self[3][@"succeeded"], @0);
  XCTAssertEqualObjects(self[3][@"event"], @"end-ocunit");
}

@end
