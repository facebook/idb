/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBBundleDescriptor;

/**
 Group of conveince methods for dealing with directories
 */
@interface FBStorageUtils : NSObject

#pragma mark Finding Files

/**
 Finds files with given extensions and buckets them.
 Note this doesn't recurse into subdirectories.

 @param extensions File extensions to find e.g. doc / zip / ...
 @param directory The directory to search in.
 @param error Error set if there was not exactly one matching file
 @return A mapping of extensions to found files.
 */
+ (nullable NSDictionary<NSString *, NSSet<NSURL *> *> *)bucketFilesWithExtensions:(nonnull NSSet<NSString *> *)extensions inDirectory:(nonnull NSURL *)directory error:(NSError * _Nullable * _Nullable)error;

/**
 Find a file with a given extension in the given directory.
 Note this doesn't recurse into subdirectories and will error if more
 than one matching file exists

 @param extension File extension to find e.g. doc / zip / ...
 @param url File URL of the directory to search in
 @param error Error set if there was not exactly one matching file
 @return NSURL * of the selected file
 */
+ (nullable NSURL *)findFileWithExtension:(nonnull NSString *)extension atURL:(nonnull NSURL *)url error:(NSError * _Nullable * _Nullable)error;

/**
 Find files with a given extension in the given directory.
 Note this doesn't recurse into subdirectories and may return an empty set

 @param extension File extension to find e.g. doc / zip / ...
 @param url File URL of the directory to search in
 @param error Error set if we couldnt read this directory
 @return Set of NSURL's to these files
 */
+ (nullable NSSet<NSURL *> *)findFilesWithExtension:(nonnull NSString *)extension atURL:(nonnull NSURL *)url error:(NSError * _Nullable * _Nullable)error;

/**
 Finds a unique file within a directory.

 @param directory the directory to search in.
 @return a the URL if a unique file could be foudn.
 */
+ (nullable NSURL *)findUniqueFileInDirectory:(nonnull NSURL *)directory error:(NSError * _Nullable * _Nullable)error;

/**
 Obtains all files within a directory

 @return the list of file URLs in the directory, or nil on error.
 */
+ (nullable NSArray<NSURL *> *)filesInDirectory:(nonnull NSURL *)directory error:(NSError * _Nullable * _Nullable)error;

/**
 Attempt to find a bundle in a directory.

 @param directory the directory to search.
 @param error an error out for any error that occurs.
 */
+ (nullable FBBundleDescriptor *)bundleInDirectory:(nonnull NSURL *)directory error:(NSError * _Nullable * _Nullable)error;

@end
