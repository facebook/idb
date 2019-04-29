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
 Obtains Application Bundle from an input file path.
 If the file path is a .app, this is used immediately and no extracting needs to take place.
 If the file path is an archive of some kind, this is extracted and then an .app is found inside the archive.
 When the context is torn down, the temporary extracted path will be deleted.

 @param queue the queue to extract on.
 @param path the path of the .app or .ipa
 @param logger the (optional) logger to log to.
 @return a future context the application bundle.
 */
+ (FBFutureContext<FBApplicationBundle *> *)onQueue:(dispatch_queue_t)queue findOrExtractApplicationAtPath:(NSString *)path logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Obtains an extracted version of an Application based on a stream of archive data.
 This will transparently create a temporary directory that contains the extracted app.
 When the context is torn down, the temporary extracted app will be deleted.

 @param queue the queue to extract on.
 @param input the input to pipe from
 @param logger the (optional) logger to log to.
 @return a future context wrapping the application bundle.
 */
+ (FBFutureContext<FBApplicationBundle *> *)onQueue:(dispatch_queue_t)queue extractApplicationFromInput:(FBProcessInput *)input logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Attempts to find an app path from a directory.
 This can be used to inspect an extracted archive and attempt to find a .app inside it.

 @param directory the directory to search.
 @return a future wrapping the application bundle.
 */
+ (FBFuture<FBApplicationBundle *> *)findAppPathFromDirectory:(NSURL *)directory;

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
