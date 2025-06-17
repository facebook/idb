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

+ (FBBundleDescriptor *)findAppPathFromDirectory:(NSURL *)directory error:(NSError **)error
{
  NSDirectoryEnumerator *directoryEnumerator = [NSFileManager.defaultManager
    enumeratorAtURL:directory
    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
    options:0
    errorHandler:nil];
  NSSet<NSURL*> *applicationURLs = [NSSet set];
  for (NSURL *fileURL in directoryEnumerator) {
    if ([FBBundleDescriptor isApplicationAtPath:fileURL.path]) {
      applicationURLs = [applicationURLs setByAddingObject:fileURL];
      [directoryEnumerator skipDescendants];
    }
  }
  if (applicationURLs.count != 1) {
    return [[FBControlCoreError
      describeFormat:@"Expected only one Application in IPA, found %lu: %@", applicationURLs.count, [FBCollectionInformation oneLineDescriptionFromArray:[applicationURLs.allObjects valueForKey:@"lastPathComponent"]]]
      fail:error];
  }
  FBBundleDescriptor *bundle = [FBBundleDescriptor bundleFromPath:applicationURLs.allObjects.firstObject.path error:error];
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
