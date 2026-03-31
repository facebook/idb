/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

@protocol FBiOSTarget;

@interface FBXCTestResultBundleParser : NSObject

+ (nonnull FBFuture<NSNull *> *)parse:(nonnull NSString *)resultBundlePath target:(nonnull id<FBiOSTarget>)target reporter:(nonnull id<FBXCTestReporter>)reporter logger:(nonnull id<FBControlCoreLogger>)logger extractScreenshots:(BOOL)extractScreenshots;

@end
