/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBApplicationBundle.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;

@class FBProcessInput;

/**
 A Bundle Descriptor specialized to Applications
 */
@interface FBApplicationBundle (Install)

#pragma mark Public Methods

/**
 Obtains an extracted version of an Application based on a the file path of an archive.
 When the context is torn down, the temporary extracted path will be deleted.

 @param queue the queue to extract on.
 @param path the path of the .app or .ipa
 @param logger the (optional) logger to log to.
 @return a future context wrapping the extracted application.
 */
+ (FBFutureContext<FBApplicationBundle *> *)onQueue:(dispatch_queue_t)queue findOrExtractApplicationAtPath:(NSString *)path logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Obtains an extracted version of an Application based on a file path.
 When the context is torn down, the temporary extracted path will be deleted.

 @param queue the queue to extract on.
 @param input the input to pipe from
 @param logger the (optional) logger to log to.
 @return a future context wrapping the extracted application.
 */
+ (FBFutureContext<FBApplicationBundle *> *)onQueue:(dispatch_queue_t)queue findOrExtractApplicationFromInput:(FBProcessInput *)input logger:(nullable id<FBControlCoreLogger>)logger;

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
