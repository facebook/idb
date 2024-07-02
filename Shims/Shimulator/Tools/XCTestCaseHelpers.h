/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class XCTestCase, XCTestSuite, NSString;

void parseXCTestCase(XCTestCase *testCase, NSString **classNameOut, NSString **methodNameOut, NSString **testKeyOut);

NSString *parseXCTestSuiteKey(XCTestSuite *suite);
