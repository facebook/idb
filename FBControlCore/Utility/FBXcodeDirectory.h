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
 
 @return a future wrapping the developer directory
 */
+ (FBFuture<NSString *> *)xcodeSelectDeveloperDirectory;

/**
 Since Xcode 6, /var/db/xcode_select_link is the path that xcode-select(1) reads and writes to.
 As such, making a process to xcode-select is an excessive overhead that can be removed.
 
 @param error an error out for any error that occurs
 @return the path if it is valid, nil otherwise.
 */
+ (nullable NSString *)symlinkedDeveloperDirectoryWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
