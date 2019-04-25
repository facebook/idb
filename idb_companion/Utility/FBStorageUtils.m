/**
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

+ (NSURL *)findFileWithExtension:(NSString *)extension atURL:(NSURL *)url error:(NSError **)error
{
  NSSet<NSURL *> *files = [self findFilesWithExtension:extension atURL:url error:error];
  if (!files) {
    return nil;
  }
  if (files.count != 1) {
    return [[FBIDBError describe:
             [NSString stringWithFormat:@"%lu files with extension .%@ in %@", (unsigned long)files.count, extension, url]]
            fail:error];
  }

  return files.anyObject;
}

+ (NSSet<NSURL *> *)findFilesWithExtension:(NSString *)extension atURL:(NSURL *)url error:(NSError **)error
{
  NSArray<NSURL *> *dirFiles =
  [[NSFileManager defaultManager] contentsOfDirectoryAtURL:url
                                includingPropertiesForKeys:nil
                                                   options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                                     error:error];
  if (!dirFiles) {
    return nil;
  }

  NSMutableSet<NSURL *> *matchingFiles = [NSMutableSet set];
  for (NSURL *file in dirFiles) {
    if ([[file pathExtension] isEqualToString:extension]) {
      [matchingFiles addObject:file];
    }
  }

  return matchingFiles;
}

+ (FBFuture<NSURL *> *)getUniqueFileInDirectory:(NSURL *)directory onQueue:(dispatch_queue_t)queue
{
  return [[self
    getFilesInDirectory:directory]
    onQueue:queue fmap:^FBFuture<NSURL *> *(NSArray<NSURL *> *filesInDirectory) {
      if (filesInDirectory.count != 1) {
        return [[FBIDBError describeFormat:@"Expected one top level file, found %lu", filesInDirectory.count] failFuture];
      }
      return [FBFuture futureWithResult:filesInDirectory[0]];
  }];
}

+ (FBFuture<NSArray<NSURL *> *> *)getFilesInDirectory:(NSURL *)directory
{
  NSError *error;
  NSArray<NSURL *> *filesInTar = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:&error];
  if (filesInTar == nil) {
    return [[[FBIDBError describeFormat:@"Failed to list files in directory"] causedBy:error] failFuture];
  }
  return [FBFuture futureWithResult:filesInTar];
}

@end
