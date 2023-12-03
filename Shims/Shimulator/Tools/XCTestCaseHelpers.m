/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


#import "XCTestCaseHelpers.h"

#import <Foundation/Foundation.h>

#import "XCTestPrivate.h"

void parseXCTestCase(XCTestCase *testCase, NSString **classNameOut, NSString **methodNameOut, NSString **testKeyOut)
{
  NSString *className = NSStringFromClass(testCase.class);
  NSString *methodName;
  if ([testCase respondsToSelector:@selector(languageAgnosticTestMethodName)]) {
    methodName = [testCase languageAgnosticTestMethodName];
  } else {
    methodName = NSStringFromSelector([testCase.invocation selector]);
  }
  NSString *testKey = [NSString stringWithFormat:@"-[%@ %@]", className, methodName];
  if (classNameOut) {
    *classNameOut = className;
  }
  if (methodNameOut) {
    *methodNameOut = methodName;
  }
  if (testKeyOut) {
    *testKeyOut = testKey;
  }
}

NSString *parseXCTestSuiteKey(XCTestSuite *suite)
{
  NSString *testKey = nil;
  for (id test in suite.tests) {
    if (![test isKindOfClass:NSClassFromString(@"XCTestCase")]) {
      return [suite name];
    }
    XCTestCase *testCase = test;
    NSString *innerTestKey = nil;
    parseXCTestCase(testCase, &innerTestKey, nil, nil);
    if (!testKey) {
      testKey = innerTestKey;
      continue;
    }
    if (![innerTestKey isEqualToString:testKey]) {
      return [suite name];
    }
  }
  return testKey ?: [suite name];
}
