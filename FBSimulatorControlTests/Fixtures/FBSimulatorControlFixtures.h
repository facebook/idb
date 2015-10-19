/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorApplication;

/**
 Fixtures for Tests.
 */
@interface FBSimulatorControlFixtures : NSObject

/**
 A build of Apple's 'Table Search' Sample Application.
 Source is available at: https://developer.apple.com/library/ios/samplecode/TableSearch_UISearchController/Introduction/Intro.html#//apple_ref/doc/uid/TP40014683
 */
+ (FBSimulatorApplication *)tableSearchApplicationWithError:(NSError **)error;

/**
 A File Path to the first photo.
 */
+ (NSString *)photo0Path;

/**
 A File Path to the second photo.
 */
+ (NSString *)photo1Path;

@end
