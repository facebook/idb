/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@class FBBundleDescriptor;

/**
 Fetching Fixtures, causing test failures if they cannot be obtained.
 */
@interface XCTestCase (FBXCTestBootstrapFixtures)

/**
 An iOS Unit Test Bundle.
 */
+ (NSBundle *)iosUnitTestBundleFixture;

/**
 An macOS Unit Test Bundle.
 */
+ (NSBundle *)macUnitTestBundleFixture;

/**
 An macOS dummy application
 */
+ (FBBundleDescriptor *)macCommonApplicationWithError:(NSError **)error;

@end
