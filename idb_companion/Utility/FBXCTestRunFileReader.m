/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestDescriptor.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestRunFileReader.h"
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
  // dictionaryWithContentsOfURL:error: is only available in NSDictionary not in NSMutableDictionary
  NSMutableDictionary<NSString *, id> *xctestrunContents = [[NSDictionary dictionaryWithContentsOfURL:xctestrunURL error:error] mutableCopy];
  if (!xctestrunContents) {
    return nil;
  }
  for (NSString *testTarget in xctestrunContents) {
    if ([testTarget isEqualToString:@"__xctestrun_metadata__"] || [testTarget isEqualToString:@"CodeCoverageBuildableInfos"]) {
      continue;
    }
    NSMutableDictionary<NSString *, id> *testTargetProperties = [[xctestrunContents objectForKey:testTarget] mutableCopy];
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
      [testTargetProperties setObject:targetAppPath forKey:@"UITargetAppPath"];
    }
    [xctestrunContents setObject:testTargetProperties forKey:testTarget];
  }
  return xctestrunContents;
}

@end
