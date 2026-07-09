/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 A String Enum for Test Types.
 */
typedef NSString *FBXCTestType NS_STRING_ENUM;

extern FBXCTestType const _Nonnull FBXCTestTypeUITest;
static NSString *_Nonnull const FBXCTestTypeApplicationTestValue = @"application-test";
extern FBXCTestType const _Nonnull FBXCTestTypeApplicationTest;
extern FBXCTestType const _Nonnull FBXCTestTypeLogicTest;
extern FBXCTestType const _Nonnull FBXCTestTypeListTest;

typedef NS_OPTIONS(NSUInteger, FBLogicTestMirrorLogs) {
  FBLogicTestMirrorNoLogs = 0,
  FBLogicTestMirrorFileLogs = 1 << 0,
  FBLogicTestMirrorLogger = 1 << 1,
};

@class FBListTestConfiguration;
@class FBLogicTestConfiguration;
@class FBTestManagerTestConfiguration;
@class FBXCTestConfiguration;
