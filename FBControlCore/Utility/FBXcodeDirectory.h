/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Obtains the Path to the Current Xcode Install.
 */
@interface FBXcodeDirectory : NSObject

/**
 The Xcode install path, using xcode-select(1).
 */
@property (nonatomic, copy, class, readonly) FBXcodeDirectory *xcodeSelectFromCommandLine;

/**
 Returns the Path to the Xcode Install.

 @param error error out for any error that occurs.
 @return the Xcode Path if successful, NO otherwise.
 */
- (nullable NSString *)xcodePathWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
