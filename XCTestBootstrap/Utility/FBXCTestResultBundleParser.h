/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>


NS_ASSUME_NONNULL_BEGIN

@protocol FBiOSTarget;

@interface FBXCTestResultBundleParser : NSObject

+ (FBFuture<NSNull *> *)parse:(NSString *)resultBundlePath target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger extractScreenshots:(BOOL)extractScreenshots;

@end

NS_ASSUME_NONNULL_END
