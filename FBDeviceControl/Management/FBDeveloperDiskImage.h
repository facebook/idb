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

@class FBDevice;

@interface FBDeveloperDiskImage : NSObject

#pragma mark Initializers

/**
 Finds the path of the Device Support disk image, if one can be found.

 @param error an error out for any error that occurs.
 @return the path of the disk image.
 */
+ (nullable FBDeveloperDiskImage *)developerDiskImage:(FBDevice *)device error:(NSError **)error;

#pragma mark Properties

/**
 The path of the disk image.
 */
@property (nonatomic, copy, readonly) NSString *diskImagePath;

/**
 The path of the signature.
 */
@property (nonatomic, copy, readonly) NSData *signature;

@end

NS_ASSUME_NONNULL_END
