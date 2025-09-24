/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBundleDescriptor+Application.h"

#import "FBArchiveOperations.h"
#import "FBBinaryDescriptor.h"
#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBProcess.h"
#import "FBProcessBuilder.h"

@implementation FBBundleDescriptor (Application)

#pragma mark Public

+ (FBBundleDescriptor *)findAppPathFromDirectory:(NSURL *)directory logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSDirectoryEnumerator *directoryEnumerator = [NSFileManager.defaultManager
    enumeratorAtURL:directory
    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
    options:0
    errorHandler:nil];
  NSMutableArray<NSString *> *applicationPaths = NSMutableArray.array;
  NSMutableArray<NSString *> *nonApplicationPaths = NSMutableArray.array;
  [logger logFormat:@"Finding Application Path from root directory %@", directory];
  for (NSURL *fileURL in directoryEnumerator) {
    NSString *path = fileURL.path;
    if ([FBBundleDescriptor isApplicationAtPath:path]) {
      [logger logFormat:@"Found application at path %@", path];
      [applicationPaths addObject:path];
      [directoryEnumerator skipDescendants];
    } else {
      [logger logFormat:@"Non-application path at %@", path];
      [nonApplicationPaths addObject:path];
    }
  }
  if (applicationPaths.count == 0) {
    return [[FBControlCoreError
      describeFormat:@"Could not find an Application in IPA, present files %@", [FBCollectionInformation oneLineDescriptionFromArray:[nonApplicationPaths valueForKey:@"lastPathComponent"]]]
      fail:error];
  }
  if (applicationPaths.count > 1) {
    return [[FBControlCoreError
      describeFormat:@"Expected only one Application in IPA, found %lu: %@", applicationPaths.count, [FBCollectionInformation oneLineDescriptionFromArray:[applicationPaths valueForKey:@"lastPathComponent"]]]
      fail:error];
  }
  NSString *applicationPath = applicationPaths.firstObject;
  [logger logFormat:@"Using Application at path %@", applicationPath];
  FBBundleDescriptor *bundle = [FBBundleDescriptor bundleFromPath:applicationPath error:error];
  [logger logFormat:@"Bundle in IPA is %@", bundle];
  if (!bundle) {
    return nil;
  }
  return bundle;
}

+ (BOOL)isApplicationAtPath:(NSString *)path
{
  BOOL isDirectory = NO;
  return path != nil
    && [path hasSuffix:@".app"]
    && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]
    && isDirectory;
}

@end
