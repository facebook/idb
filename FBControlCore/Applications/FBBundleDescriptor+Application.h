/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBBundleDescriptor.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;

@class FBProcessInput;

/**
 Operations on FBBundleDescriptor, for applications.
 */
@interface FBBundleDescriptor (Application)

#pragma mark Public Methods

/**
 Attempts to find an app path from a directory.
 This can be used to inspect an extracted archive and attempt to find a .app inside it.

 @param directory the directory to search.
 @return a future wrapping the application bundle.
 */
+ (FBFuture<FBBundleDescriptor *> *)findAppPathFromDirectory:(NSURL *)directory;

/**
 Check if given path is an application path.

 @param path the path to check.
 @return if the path is an application path.
 */
+ (BOOL)isApplicationAtPath:(NSString *)path;

/**
 Returns a FBBundleDescriptor for a given .app path

 @param appPath path to an .app
 @return future wrapping a FBBundleDescriptor for this app
 */
+ (FBFuture<FBBundleDescriptor *> *)extractedApplicationAtPath:(NSString *)appPath;

@end

NS_ASSUME_NONNULL_END
