/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBApplicationDescriptor;

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

@end
