/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBBundleDescriptor.h>
#import <FBControlCore/FBFuture.h>

/**
 Operations on FBBundleDescriptor, for applications.
 */
@interface FBBundleDescriptor (Application)

#pragma mark Public Methods

/**
 Attempts to find an app path from a directory.
 This can be used to inspect an extracted archive and attempt to find a .app inside it.

 @param directory the directory to search.
 @param logger the logger to log to.
 @return an FBBundleDescriptor for the application bundle, or nil on error.
 */
+ (nullable FBBundleDescriptor *)findAppPathFromDirectory:(nonnull NSURL *)directory logger:(nullable id<FBControlCoreLogger>)logger error:(NSError * _Nullable * _Nullable)error;

/**
 Check if given path is an application path.

 @param path the path to check.
 @return if the path is an application path.
 */
+ (BOOL)isApplicationAtPath:(nonnull NSString *)path;

@end
