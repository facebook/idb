/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
