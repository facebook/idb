/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Static Fixtures for FBXCTestKitTests
 */
@interface FBXCTestKitFixtures : NSObject

/**
 Creates a new temporary directory.

 @return path to temporary directory.
 */
+ (NSString *)createTemporaryDirectory;

/**
 A build of Apple's 'Table Search' Sample Application.
 Source is available at:
 https://developer.apple.com/library/ios/samplecode/TableSearch_UISearchController/Introduction/Intro.html#//apple_ref/doc/uid/TP40014683

 @return path to the application.
 */
+ (NSString *)tableSearchApplicationPath;

+ (NSString *)testRunnerApp;

/**
 An iOS Unit Test XCTest Target.

 @return path to the Unit Test Bundle.
 */
+ (NSString *)iOSUnitTestBundlePath;

/**
 An Mac Unit Test XCTest Target.

 @return path to the Unit Test Bundle.
 */
+ (NSString *)macUnitTestBundlePath;

/**
 An Mac UITest XCTest Target.

 @return path to the UITest Bundle.
 */
+ (NSString *)macUITestBundlePath;

/**
 An Mac Application used for hosting tests

 @return path to the Application.
 */
+ (NSString *)macCommonAppPath;

/**
 A build of Application used by macUITestBundlePath.

 @return path to the Application.
 */
+ (NSString *)macUITestAppTargetPath;

/**
 A build of Application used by iOSUITestBundlePath.

 @return path to the Application.
 */
+ (NSString *)iOSUITestAppTargetPath;

/**
 An iOS UI Test XCTest Target.

 @return path to the UI Test Bundle.
 */
+ (NSString *)iOSUITestBundlePath;

/**
 An iOS App Test XCTest Target.

 @return path to the App Test Bundle.
 */
+ (NSString *)iOSAppTestBundlePath;

@end

/**
 Conveniences for getting fixtures.
 */
@interface XCTestCase (FBXCTestKitTests)

/**
 An iOS Unit Test XCTest Target.
 Will check that the bundle is codesigned, and sign it if is not.

 @return path to the Unit Test Bundle.
 */
- (nullable NSString *)iOSUnitTestBundlePath;

/**
 An iOS UITest XCTest Target.
 Will check that the bundle is codesigned, and sign it if is not.

 @return path to the UITest Bundle.
 */
- (nullable NSString *)iOSUITestBundlePath;

/**
 An iOS AppTest XCTest Target.
 Will check that the bundle is codesigned, and sign it if is not.

 @return path to the AppTest Bundle.
 */
- (nullable NSString *)iOSAppTestBundlePath;

@end

NS_ASSUME_NONNULL_END
