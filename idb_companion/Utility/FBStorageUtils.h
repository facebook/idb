/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>

@class FBApplicationBundle;

NS_ASSUME_NONNULL_BEGIN

/**
 Group of conveince methods for dealing with directories
 */
@interface FBStorageUtils : NSObject

#pragma mark Finding Files

/**
 Find a file with a given extension in the given directory.
 Note this doesn't recurse into subdirectories and will error if more
 than one matching file exists

 @param extension File extension to find e.g. doc / zip / ...
 @param url File URL of the directory to search in
 @param error Error set if there was not exactly one matching file
 @return NSURL * of the selected file
 */
+ (nullable NSURL *)findFileWithExtension:(NSString *)extension atURL:(NSURL *)url error:(NSError **)error;

/**
 Find files with a given extension in the given directory.
 Note this doesn't recurse into subdirectories and may return an empty set

 @param extension File extension to find e.g. doc / zip / ...
 @param url File URL of the directory to search in
 @param error Error set if we couldnt read this directory
 @return Set of NSURL's to these files
 */
+ (nullable NSSet<NSURL *> *)findFilesWithExtension:(NSString *)extension atURL:(NSURL *)url error:(NSError **)error;

#pragma mark Private

/**
 Finds a unique file within a directory.

 @param directory the directory to search in.
 @param queue the queue to use.
 @return a Future wrapping the unique file.
 */
+ (FBFuture<NSURL *> *)getUniqueFileInDirectory:(NSURL *)directory onQueue:(dispatch_queue_t)queue;

/**
 Obtains all files within a directory

 @return a Future wrapping the list of files.
 */
+ (FBFuture<NSArray<NSURL *> *> *)getFilesInDirectory:(NSURL *)directory;

@end

NS_ASSUME_NONNULL_END
