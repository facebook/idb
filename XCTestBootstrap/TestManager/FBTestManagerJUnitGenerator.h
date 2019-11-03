/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestManagerTestReporterTestSuite;

/**
 Transforms a graph of FBTestManagerTestReporterTestSuite objects into
 an NSXMLDocument representation of the JUnit format.
 */
@interface FBTestManagerJUnitGenerator : NSObject

/**
 Generates JUnit XML document for given test suite.

 @param testSuite the test suite to transform.
 @return an NSXMLDocument instance.
 */
+ (NSXMLDocument *)documentForTestSuite:(FBTestManagerTestReporterTestSuite *)testSuite;

/**
 Generates JUnit XML document for given array of test suite elements.

 @param testSuiteElements the test suite XML element.
 @return an NSXMLDocument instance.
 */
+ (NSXMLDocument *)documentForTestSuiteElements:(NSArray<NSXMLElement *> *)testSuiteElements;

/**
 Generates an XML node for the given Test Suite object and prefixes all Test Case names
 with the given package prefix.

 @param testSuite the test suite to transform.
 @param packagePrefix the package prefix to prepend on each test case class name.
 @return an NSXMLDocument instance.
 */
+ (NSXMLElement *)elementForTestSuite:(FBTestManagerTestReporterTestSuite *)testSuite packagePrefix:(nullable NSString *)packagePrefix;

@end

NS_ASSUME_NONNULL_END
