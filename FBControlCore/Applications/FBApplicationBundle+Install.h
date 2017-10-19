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
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A value for an extracted application.
 */
@interface FBExtractedApplication : NSObject

@property (nonatomic, copy, readonly) FBApplicationBundle *bundle;

@property (nonatomic, copy, readonly) NSURL *extractedPath;

@end

/**
 A Bundle Descriptor specialized to Applications
 */
@interface FBApplicationBundle (Install)

#pragma mark Public Methods

/**
 Finds or Extracts an Application if it is determined to be an IPA.

 @param queue the queue to extract on.
 @param path the path of the .app or .ipa
 @return a future wrapping the extracted application.
 */
+ (FBFuture<FBExtractedApplication *> *)onQueue:(dispatch_queue_t)queue findOrExtractApplicationAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
