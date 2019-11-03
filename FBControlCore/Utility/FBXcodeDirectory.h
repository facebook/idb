/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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
 The Xcode install path, using xcode-select(1).
 */
@property (nonatomic, copy, class, readonly) FBXcodeDirectory *xcodeSelectFromCommandLine;

#pragma mark Public Methods

/**
 Finds the file path of the Xcode install.

 @return a future that resolves with the path
 */
- (FBFuture<NSString *> *)xcodePath;

@end

NS_ASSUME_NONNULL_END
