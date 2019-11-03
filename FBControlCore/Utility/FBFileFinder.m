/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFileFinder.h"

#include <glob.h>

@implementation FBFileFinder

+ (NSArray<NSString *> *)recursiveFindFiles:(NSArray<NSString *> *)filenames inDirectory:(NSString *)directory
{
  NSParameterAssert(filenames);
  NSParameterAssert(directory);

  BOOL isDirectory = NO;
  if (![NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&isDirectory]) {
    return @[];
  }
  if (!isDirectory) {
    return @[];
  }

  NSSet *filenameSet = [NSSet setWithArray:filenames];
  NSMutableSet *foundFiles = [NSMutableSet set];
  NSString *currentFile = nil;
  NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:directory];

  while ((currentFile = enumerator.nextObject)) {
    if (![filenameSet containsObject:currentFile.lastPathComponent]) {
      continue;
    }
    [foundFiles addObject:[directory stringByAppendingPathComponent:currentFile]];
  }
  return [foundFiles allObjects];
}

+ (NSArray<NSString *> *)recursiveFindByFilenameGlobs:(NSArray<NSString *> *)filenameGlobs inDirectory:(NSString *)directory
{
  NSParameterAssert(filenameGlobs);
  NSParameterAssert(directory);

  BOOL isDirectory = NO;
  if (![NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&isDirectory]) {
    return @[];
  }
  if (!isDirectory) {
    return @[];
  }

  NSMutableArray<NSString *> *foundFiles = [NSMutableArray array];

  NSArray<NSString *> *subdirectories = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:directory error:nil];
  NSEnumerator *dirsEnumerator = [subdirectories objectEnumerator];
  NSString *subdirectory;
  while (subdirectory = [dirsEnumerator nextObject]) {
    NSString *fullDirectory = [directory stringByAppendingPathComponent:subdirectory];

    for (NSString *filenameGlob in filenameGlobs) {
      NSString *globPathComponent = [NSString stringWithFormat: @"/%@", filenameGlob];
      const char *fullPattern = [[fullDirectory stringByAppendingPathComponent: globPathComponent] UTF8String];

      glob_t gt;
      if (glob(fullPattern, 0, NULL, &gt) == 0) {
        for (int i = 0; i < gt.gl_matchc; i++) {
          size_t len = strlen(gt.gl_pathv[i]);
          NSString *filePath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:gt.gl_pathv[i] length:len];

          if (![NSFileManager.defaultManager fileExistsAtPath:filePath isDirectory:&isDirectory]) {
            continue;
          }
          if (isDirectory) {
            continue; // Don't copy directory.
          }

          [foundFiles addObject:filePath];
        }
      }
      globfree(&gt);
    }
  }

  return [NSArray arrayWithArray:foundFiles];
}

+ (NSArray<NSString *> *)mostRecentFindFiles:(NSArray<NSString *> *)filenames inDirectory:(NSString *)directory
{
  NSArray *allPaths = [self recursiveFindFiles:filenames inDirectory:directory];
  NSMutableDictionary<NSString *, NSDate *> *dates = [NSMutableDictionary dictionary];
  for (NSArray *filename in filenames) {
    dates[filename] = NSDate.distantPast;
  }
  NSMutableDictionary<NSString *, NSString *> *paths = [NSMutableDictionary dictionary];
  for (NSString *path in allPaths) {
    NSDate *date = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileModificationDate];
    NSString *filename = path.lastPathComponent;
    if (!date) {
      continue;
    }
    if ([dates[filename] compare:date] != NSOrderedAscending) {
      continue;
    }
    dates[filename] = date;
    paths[filename] = path;
  }
  return [paths allValues];
}

+ (NSArray<NSString *> *)contentsOfDirectoryWithBasePath:(NSString *)basePath
{
  NSMutableArray<NSString *> *contents = [NSMutableArray array];
  for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:basePath error:nil] ?: @[]) {
    NSString *path = [basePath stringByAppendingPathComponent:file];
    [contents addObject:path];
  }
  return [contents copy];
}

@end
