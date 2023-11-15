/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestRunFileReader.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBIDBStorageManager.h"

@implementation FBXCTestRunFileReader : NSObject

+ (NSDictionary<NSString *, id> *)readContentsOf:(NSURL *)xctestrunURL expandPlaceholderWithPath:(NSString *)path error:(NSError **)error
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  if(![fileManager fileExistsAtPath:[xctestrunURL path]]) {
    return [[FBXCTestError
      describeFormat:@"xctestrun file does not exist at expected location: %@", xctestrunURL]
      fail:error];
  }
  NSString *testRoot = [[xctestrunURL path] stringByDeletingLastPathComponent];
  NSString *idbAppStoragePath = [path stringByAppendingPathComponent:IdbApplicationsFolder];
  if (![fileManager fileExistsAtPath:idbAppStoragePath]) {
    return [[FBXCTestError
      describeFormat:@"IDB app storage folder does not exist at: %@", idbAppStoragePath]
      fail:error];
  }
  NSDictionary<NSString *, id> *xctestrunContents = [NSDictionary dictionaryWithContentsOfURL:xctestrunURL error:error];
  NSMutableDictionary<NSString *, id> *mutableContents = [NSMutableDictionary dictionaryWithCapacity:xctestrunContents.count];
  if (!xctestrunContents) {
    return nil;
  }
  for (NSString *contentKey in xctestrunContents) {
    if ([contentKey isEqualToString:@"__xctestrun_metadata__"] || [contentKey isEqualToString:@"CodeCoverageBuildableInfos"]) {
      [mutableContents setObject:xctestrunContents[contentKey] forKey:contentKey];
      continue;
    }
    NSMutableDictionary<NSString *, id> *testTargetProperties = [[xctestrunContents objectForKey:contentKey] mutableCopy];
    // Expand __TESTROOT__ and __IDB_APPSTORAGE__ in TestHostPath
    NSString *testHostPath = [testTargetProperties objectForKey:@"TestHostPath"];
    if (testHostPath != nil) {
      testHostPath = [testHostPath stringByReplacingOccurrencesOfString:@"__TESTROOT__" withString:testRoot];
      testHostPath = [testHostPath stringByReplacingOccurrencesOfString:@"__IDB_APPSTORAGE__" withString:idbAppStoragePath];
      [testTargetProperties setObject:testHostPath forKey:@"TestHostPath"];
    }
    // Expand __TESTROOT__ and __TESTHOST__ in TestBundlePath
    NSString *testBundlePath = [testTargetProperties objectForKey:@"TestBundlePath"];
    if (testBundlePath != nil) {
      testBundlePath = [testBundlePath stringByReplacingOccurrencesOfString:@"__TESTROOT__" withString:testRoot];
      testBundlePath = [testBundlePath stringByReplacingOccurrencesOfString:@"__TESTHOST__" withString:testHostPath];
      [testTargetProperties setObject:testBundlePath forKey:@"TestBundlePath"];
    }
    // Expand __IDB_APPSTORAGE__ in UITargetAppPath
    NSString *targetAppPath = [testTargetProperties objectForKey:@"UITargetAppPath"];
    if (targetAppPath != nil) {
      targetAppPath = [targetAppPath stringByReplacingOccurrencesOfString:@"__IDB_APPSTORAGE__" withString:idbAppStoragePath];
      targetAppPath = [targetAppPath stringByReplacingOccurrencesOfString:@"__TESTROOT__" withString:testRoot];
      [testTargetProperties setObject:targetAppPath forKey:@"UITargetAppPath"];
    }
    NSArray<NSString *> *dependencies = [testTargetProperties objectForKey:@"DependentProductPaths"];
    if (dependencies && dependencies.count) {
      NSMutableArray<NSString *> *expandedDeps = [NSMutableArray arrayWithCapacity:dependencies.count];
      for (NSString *dep in dependencies) {
          NSString *absPath = [dep stringByReplacingOccurrencesOfString:@"__IDB_APPSTORAGE__" withString:idbAppStoragePath];
          absPath = [absPath stringByReplacingOccurrencesOfString:@"__TESTROOT__" withString:testRoot];
          [expandedDeps addObject:absPath];
      }
      [testTargetProperties setObject:[NSArray arrayWithArray:expandedDeps] forKey:@"DependentProductPaths"];
    }
    [mutableContents setObject:testTargetProperties forKey:contentKey];
  }
  return [NSDictionary dictionaryWithDictionary:mutableContents];
}

@end
