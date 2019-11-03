/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBStorageUtils.h"

#import <FBControlCore/FBControlCore.h>

#import "FBIDBError.h"

@implementation FBStorageUtils

#pragma mark Finding Files

+ (NSDictionary<NSString *, NSSet<NSURL *> *> *)bucketFilesWithExtensions:(NSSet<NSString *> *)extensions inDirectory:(NSURL *)directory error:(NSError **)error
{
  NSMutableDictionary<NSString *, NSMutableSet<NSURL *> *> *files = NSMutableDictionary.dictionary;
  for (NSString *extension in extensions) {
    files[extension] = NSMutableSet.set;
  }

  NSArray<NSURL *> *contents = [NSFileManager.defaultManager
    contentsOfDirectoryAtURL:directory
    includingPropertiesForKeys:nil
    options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
    error:error];

  if (!contents) {
    return nil;
  }
  for (NSURL *file in contents) {
    NSString *extension = file.pathExtension;
    if (![extensions containsObject:extension]) {
      continue;
    }
    NSMutableSet<NSURL *> *bucket = files[extension];
    [bucket addObject:file];
  }

  return files;
}

+ (NSURL *)findFileWithExtension:(NSString *)extension atURL:(NSURL *)url error:(NSError **)error
{
  NSSet<NSURL *> *files = [self findFilesWithExtension:extension atURL:url error:error];
  if (!files) {
    return nil;
  }
  if (files.count != 1) {
    return [[FBIDBError
      describeFormat:@"%lu files with extension .%@ in %@", (unsigned long)files.count, extension, url]
      fail:error];
  }

  return files.anyObject;
}

+ (NSSet<NSURL *> *)findFilesWithExtension:(NSString *)extension atURL:(NSURL *)url error:(NSError **)error
{
  return [self bucketFilesWithExtensions:[NSSet setWithObject:extension] inDirectory:url error:error][extension];
}

+ (NSURL *)findUniqueFileInDirectory:(NSURL *)directory error:(NSError **)error
{
  NSArray<NSURL *> *filesInDirectory = [self filesInDirectory:directory error:error];
  if (!filesInDirectory) {
    return nil;
  }
  if (filesInDirectory.count != 1) {
    return [[FBIDBError
      describeFormat:@"Expected one top level file, found %lu: %@", filesInDirectory.count, [FBCollectionInformation oneLineDescriptionFromArray:filesInDirectory]]
      fail:error];
  }
  return filesInDirectory[0];
}

+ (NSArray<NSURL *> *)filesInDirectory:(NSURL *)directory error:(NSError **)error
{
  NSError *innerError;
  NSArray<NSURL *> *filesInDirectory = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:&innerError];
  if (filesInDirectory == nil) {
    return [[[FBIDBError
      describeFormat:@"Failed to list files in directory %@", directory]
      causedBy:innerError]
      fail:error];
  }
  return filesInDirectory;
}

+ (FBBundleDescriptor *)bundleInDirectory:(NSURL *)directory error:(NSError **)error
{
  NSURL *uniqueFile = [self findUniqueFileInDirectory:directory error:error];
  if (!uniqueFile) {
    return nil;
  }
  return [FBBundleDescriptor bundleFromPath:uniqueFile.path error:error];
}

@end
