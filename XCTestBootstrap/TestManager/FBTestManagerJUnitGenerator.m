/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManagerJUnitGenerator.h"
#import "FBTestManagerResultSummary.h"
#import "FBTestManagerTestReporterTestCase.h"
#import "FBTestManagerTestReporterTestCaseFailure.h"
#import "FBTestManagerTestReporterTestSuite.h"

@implementation FBTestManagerJUnitGenerator

#pragma mark - JUnit XML Generator

+ (NSXMLDocument *)documentForTestSuite:(FBTestManagerTestReporterTestSuite *)testSuite
{
    return [self documentForTestSuiteElements:@[[self elementForTestSuite:testSuite packagePrefix:nil]]];
}

+ (NSXMLDocument *)documentForTestSuiteElements:(NSArray<NSXMLElement *> *)testSuiteElements
{
  NSXMLElement *testSuitesElement = [NSXMLElement elementWithName:@"testsuites"];
  for (NSXMLElement *testSuiteElement in testSuiteElements) {
    [testSuitesElement addChild:testSuiteElement];
  }
  NSXMLDocument *document = [NSXMLDocument documentWithRootElement:testSuitesElement];
  document.version = @"1.0";
  document.standalone = YES;
  document.characterEncoding = @"UTF-8";
  return document;
}

+ (NSXMLElement *)elementForTestSuite:(FBTestManagerTestReporterTestSuite *)testSuite packagePrefix:(NSString *)packagePrefix
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
    [testSuiteElement addChild:[self elementForTestCase:testCase packagePrefix:packagePrefix]];
  }

  for (FBTestManagerTestReporterTestSuite *nestedTestSuite in testSuite.testSuites) {
    [testSuiteElement addChild:[self elementForTestSuite:nestedTestSuite packagePrefix:packagePrefix]];
  }

  return testSuiteElement;
}

#pragma mark - Private

+ (NSString *)classNameForTestCase:(FBTestManagerTestReporterTestCase *)testCase packagePrefix:(NSString *)packagePrefix
{
  if (!packagePrefix.length) {
    return testCase.testClass;
  }
  return [NSString stringWithFormat:@"%@.%@", packagePrefix, testCase.testClass];
}

+ (NSXMLElement *)elementForTestCase:(FBTestManagerTestReporterTestCase *)testCase packagePrefix:(NSString *)packagePrefix
{
  NSXMLElement *testCaseElement = [NSXMLElement elementWithName:@"testcase"];
  [testCaseElement addAttribute:[NSXMLNode attributeWithName:@"classname" stringValue:[self classNameForTestCase:testCase packagePrefix:packagePrefix]]];
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

@end
