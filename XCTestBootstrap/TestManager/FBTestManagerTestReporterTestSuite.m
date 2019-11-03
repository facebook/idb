/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManagerTestReporterTestSuite.h"
#import "FBTestManagerTestReporterTestCase.h"

@interface FBTestManagerTestReporterTestSuite ()

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *startTime;
@property (nonatomic, strong, nullable) FBTestManagerResultSummary *summary;
@property (nonatomic, strong) NSMutableArray<FBTestManagerTestReporterTestCase *> *mutableTestCases;
@property (nonatomic, strong) NSMutableArray<FBTestManagerTestReporterTestSuite *> *mutableTestSuites;
@property (nonatomic, weak) FBTestManagerTestReporterTestSuite *parent;

@end

@implementation FBTestManagerTestReporterTestSuite

+ (instancetype)withName:(NSString *)name startTime:(NSString *)startTime
{
  return [[self alloc] initWithName:name startTime:startTime];
}

- (instancetype)initWithName:(NSString *)name startTime:(NSString *)startTime
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _name = [name copy];
  _startTime = [startTime copy];
  _mutableTestCases = [NSMutableArray array];
  _mutableTestSuites = [NSMutableArray array];

  return self;
}

- (NSArray<FBTestManagerTestReporterTestCase *> *)testCases
{
  return [self.mutableTestCases copy];
}

- (NSArray<FBTestManagerTestReporterTestSuite *> *)testSuites
{
  return [self.mutableTestSuites copy];
}

- (void)addTestCase:(FBTestManagerTestReporterTestCase *)testCase
{
  [self.mutableTestCases addObject:testCase];
}

- (void)addTestSuite:(FBTestManagerTestReporterTestSuite *)testSuite
{
  testSuite.parent = self;
  [self.mutableTestSuites addObject:testSuite];
}

- (void)finishWithSummary:(FBTestManagerResultSummary *)summary
{
  NSAssert(!self.summary, @"finishWithSummary: may be called only once");
  self.summary = summary;
}

#pragma mark -

- (NSString *)description
{
  return [NSString stringWithFormat:@"TestSuite %@ | Test Cases %zd | Test Suites %zd", self.name, self.testCases.count,
                                    self.testSuites.count];
}

@end
