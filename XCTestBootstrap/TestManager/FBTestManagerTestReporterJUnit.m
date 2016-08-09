/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestManagerTestReporterJUnit.h"
#import "FBTestManagerResultSummary.h"
#import "FBTestManagerTestReporterTestCase.h"
#import "FBTestManagerTestReporterTestCaseFailure.h"
#import "FBTestManagerTestReporterTestSuite.h"

@interface FBTestManagerTestReporterJUnit ()

@property (nonatomic, strong) NSFileHandle *outputFileHandle;

@end

@implementation FBTestManagerTestReporterJUnit

+ (instancetype)withOutputFileHandle:(NSFileHandle *)outputFileHandle
{
  return [[self alloc] initWithOutputFileHandle:outputFileHandle];
}

- (instancetype)initWithOutputFileHandle:(NSFileHandle *)outputFileHandle
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _outputFileHandle = outputFileHandle;

  return self;
}

#pragma mark - FBTestManagerTestReporter

- (void)testManagerMediatorDidFinishExecutingTestPlan:(FBTestManagerAPIMediator *)mediator
{
  [super testManagerMediatorDidFinishExecutingTestPlan:mediator];

  NSXMLDocument *document = [FBTestManagerTestReporterJUnit documentForTestSuite:self.testSuite];
  [self.outputFileHandle writeData:[document XMLDataWithOptions:NSXMLNodePrettyPrint]];
}

#pragma mark - JUnit XML Generator

+ (NSXMLDocument *)documentForTestSuite:(FBTestManagerTestReporterTestSuite *)testSuite
{
  NSXMLElement *testSuiteElement = [NSXMLElement elementWithName:@"testsuites"];
  [testSuiteElement addChild:[self elementForTestSuite:testSuite]];
  NSXMLDocument *document = [NSXMLDocument documentWithRootElement:testSuiteElement];
  document.version = @"1.0";
  document.standalone = YES;
  document.characterEncoding = @"UTF-8";
  return document;
}

+ (NSXMLElement *)elementForTestCase:(FBTestManagerTestReporterTestCase *)testCase
{
  NSXMLElement *testCaseElement = [NSXMLElement elementWithName:@"testcase"];
  [testCaseElement addAttribute:[NSXMLNode attributeWithName:@"classname" stringValue:testCase.testClass]];
  [testCaseElement addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:testCase.method]];
  [testCaseElement addAttribute:[NSXMLNode attributeWithName:@"time" stringValue:@(testCase.duration).stringValue]];
  for (FBTestManagerTestReporterTestCaseFailure *testCaseFailure in testCase.failures) {
    [testCaseElement addChild:[self elementForTestCaseFailure:testCaseFailure]];
  }
  return testCaseElement;
}

+ (NSXMLElement *)elementForTestCaseFailure:(FBTestManagerTestReporterTestCaseFailure *)testCaseFailure
{
  NSString *failure = [NSString stringWithFormat:@"%@:%zd", testCaseFailure.file, testCaseFailure.line];
  NSXMLElement *testCaseFailureElement = [NSXMLElement elementWithName:@"failure" stringValue:failure];
  [testCaseFailureElement addAttribute:[NSXMLNode attributeWithName:@"type" stringValue:@"Failure"]];
  [testCaseFailureElement addAttribute:[NSXMLNode attributeWithName:@"message" stringValue:testCaseFailure.message]];
  return testCaseFailureElement;
}

+ (NSXMLElement *)elementForTestSuite:(FBTestManagerTestReporterTestSuite *)testSuite
{
  NSXMLElement *testSuiteElement = [NSXMLElement elementWithName:@"testsuite"];

  NSString *runCount = @(testSuite.summary.runCount).stringValue;
  NSString *failureCount = @(testSuite.summary.failureCount).stringValue;
  NSString *errorCount = @(testSuite.summary.unexpected).stringValue;
  NSString *duration = @(testSuite.summary.totalDuration).stringValue;

  [testSuiteElement addAttribute:[NSXMLNode attributeWithName:@"tests" stringValue:runCount]];
  [testSuiteElement addAttribute:[NSXMLNode attributeWithName:@"failures" stringValue:failureCount]];
  [testSuiteElement addAttribute:[NSXMLNode attributeWithName:@"errors" stringValue:errorCount]];
  [testSuiteElement addAttribute:[NSXMLNode attributeWithName:@"time" stringValue:duration]];
  [testSuiteElement addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:testSuite.name]];

  for (FBTestManagerTestReporterTestCase *testCase in testSuite.testCases) {
    [testSuiteElement addChild:[self elementForTestCase:testCase]];
  }

  for (FBTestManagerTestReporterTestSuite *nestedTestSuite in testSuite.testSuites) {
    [testSuiteElement addChild:[self elementForTestSuite:nestedTestSuite]];
  }

  return testSuiteElement;
}

@end
