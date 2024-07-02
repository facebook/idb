/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Obtains the Path to the Current Xcode Install.
 */
@interface FBXcodeDirectory : NSObject

#pragma mark Implementations

/**
 The Xcode developer directory, from using xcode-select(1).
 */
+ (FBFuture<NSString *> *)xcodeSelectDeveloperDirectory;

@end

NS_ASSUME_NONNULL_END
