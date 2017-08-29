/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationBundle.h"

#import "FBBinaryDescriptor.h"
#import "FBBinaryParser.h"
#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBTask.h"
#import "FBTaskBuilder.h"

static BOOL deleteDirectory(NSURL *path)
{
  if (path == nil) {
    return YES;
  }
  return [[NSFileManager defaultManager] removeItemAtURL:path error:nil];
}

static BOOL isApplicationAtPath(NSString *path)
{
  BOOL isDirectory = NO;
  return path != nil
    && [path hasSuffix:@".app"]
    && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]
    && isDirectory;
}

@implementation FBApplicationBundle (Install)

// The Magic Header for Zip Files is two chars 'PK'. As a short this is as below.
static short const ZipFileMagicHeader = 0x4b50;

+ (BOOL)isIPAAtPath:(NSString *)path error:(NSError **)error
{
  // IPAs are Zip files. Zip Files always have a magic header in their first 4 bytes.
  FILE *file = fopen(path.UTF8String, "r");
  if (!file) {
    return [[FBControlCoreError
      describeFormat:@"Failed to open %@ for reading", path]
      failBool:error];
  }
  short magic = 0;
  if (!fread(&magic, sizeof(short), 1, file)) {
    fclose(file);
    return [[FBControlCoreError
      describeFormat:@"Could not read file %@ for magic zip header", path]
      failBool:error];
  }
  fclose(file);
  return magic == ZipFileMagicHeader;
}

+ (nullable NSString *)findOrExtractApplicationAtPath:(NSString *)path extractPathOut:(NSURL **)extractPathOut error:(NSError **)error
{
  // If it's an App, we don't need to do anything, just return early.
  if (isApplicationAtPath(path)) {
    return path;
  }
  // The other case is that this is an IPA, check it is before extacting.
  if (![FBApplicationBundle isIPAAtPath:path error:error]) {
    return [[FBControlCoreError
      describeFormat:@"File at path %@ is neither an IPA not a .app", path]
      fail:error];
  }

  NSString *tempDirPath = [NSTemporaryDirectory() stringByAppendingPathComponent:NSProcessInfo.processInfo.globallyUniqueString];
  NSURL *tempDirURL = [NSURL fileURLWithPath:tempDirPath isDirectory:YES];
  if (extractPathOut) {
    *extractPathOut = tempDirURL;
  }

  NSError *innerError = nil;
  if (![[NSFileManager defaultManager] createDirectoryAtURL:tempDirURL withIntermediateDirectories:YES attributes:nil error:&innerError]) {
    return [[[FBControlCoreError
      describe:@"Could not create temporary directory for IPA extraction"]
      causedBy:innerError]
      fail:error];
  }
  FBTask *task = [[[[[FBTaskBuilder withLaunchPath:@"/usr/bin/unzip"]
    withArguments:@[@"-o", @"-d", [tempDirURL path], path]]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@0]]
    build]
    startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.slowTimeout];

  if (task.error) {
    return [[[FBControlCoreError
      describeFormat:@"Could not unzip IPA at %@.", path]
      causedBy:task.error]
      fail:error];
  }

  NSDirectoryEnumerator *directoryEnumerator = [NSFileManager.defaultManager
    enumeratorAtURL:tempDirURL
    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
    options:0
    errorHandler:nil];
  NSSet *applicationURLs = [NSSet set];
  for (NSURL *fileURL in directoryEnumerator) {
    if (isApplicationAtPath([fileURL path])) {
      applicationURLs = [applicationURLs setByAddingObject:fileURL];
      [directoryEnumerator skipDescendants];
    }
  }
  if ([applicationURLs count] != 1) {
    deleteDirectory(tempDirURL);
    return [[FBControlCoreError
      describeFormat:@"Expected only one Application in IPA, found %lu", [applicationURLs count]]
      fail:error];
  }
  return [[applicationURLs anyObject] path];
}

@end
