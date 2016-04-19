/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFileFinder.h"

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
