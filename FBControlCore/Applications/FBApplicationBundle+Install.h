/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBBundleDescriptor.h>
#import <FBControlCore/FBApplicationBundle.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Bundle Descriptor specialized to Applications
 */
@interface FBApplicationBundle (Install)

#pragma mark Public Methods

/**
 Finds or Extracts an Application if it is determined to be an IPA.
 If the Path is a .app, it will be returned unchanged.

 @param path the path of the .app or .ipa
 @param extractPathOut an outparam for the path where the Application is extracted.
 @param error any error that occurred in fetching the application.
 @return the path if successful, NO otherwise.
 */
+ (nullable NSString *)findOrExtractApplicationAtPath:(NSString *)path extractPathOut:(NSURL *_Nullable* _Nullable)extractPathOut error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
