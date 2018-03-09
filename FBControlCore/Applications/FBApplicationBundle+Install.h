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

@protocol FBControlCoreLogger;

/**
 A value for an extracted application.
 */
@interface FBExtractedApplication : NSObject

/**
 The extracted Application Bundle.
 */
@property (nonatomic, copy, readonly) FBApplicationBundle *bundle;

/**
 The location of the extracted application on disk.
 */
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
 @param logger the (optional) logger to log to.
 @return a future wrapping the extracted application.
 */
+ (FBFuture<FBExtractedApplication *> *)onQueue:(dispatch_queue_t)queue findOrExtractApplicationAtPath:(NSString *)path logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Copy additional framework to Application path.

 @param appPath the path of the .app.
 @param frameworkPath the path of the framework.
 @return a future wrapping the application path.
 */
+ (NSString *)copyFrameworkToApplicationAtPath:(NSString *)appPath frameworkPath:(NSString *)frameworkPath;

/**
 Check if given path is an application path.

 @param path the path to check.
 @return if the path is an application path.
 */
+ (BOOL)isApplicationAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
