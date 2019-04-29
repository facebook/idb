/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBApplicationBundle+Install.h"

#import "FBArchiveOperations.h"
#import "FBBinaryDescriptor.h"
#import "FBBinaryParser.h"
#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBTask.h"
#import "FBTaskBuilder.h"

@implementation FBApplicationBundle (Install)

#pragma mark Public

+ (FBFutureContext<FBApplicationBundle *> *)onQueue:(dispatch_queue_t)queue findOrExtractApplicationAtPath:(NSString *)path  logger:(id<FBControlCoreLogger>)logger
{
  // If it's an App, we don't need to do anything, just return early.
  if ([FBApplicationBundle isApplicationAtPath:path]) {
    return [FBFutureContext futureContextWithFuture:[self extractedApplicationAtPath:path directory:nil]];
  }
  return [[[self
    temporaryExtractPathWithQueue:queue logger:logger]
    onQueue:queue pend:^(NSURL *extractPath) {
      return [[FBArchiveOperations extractArchiveAtPath:path toPath:extractPath.path queue:queue logger:logger] mapReplace:extractPath];
    }]
    onQueue:queue pend:^(NSURL *extractPath) {
      return [FBApplicationBundle findAppPathFromDirectory:extractPath];
    }];
}

+ (FBFutureContext<FBApplicationBundle *> *)onQueue:(dispatch_queue_t)queue extractApplicationFromInput:(FBProcessInput *)input  logger:(id<FBControlCoreLogger>)logger
{
  return [[[self
    temporaryExtractPathWithQueue:queue logger:logger]
    onQueue:queue pend:^(NSURL *extractPath) {
      return [[FBArchiveOperations extractArchiveFromStream:input toPath:extractPath.path queue:queue logger:logger] mapReplace:extractPath];
    }]
    onQueue:queue pend:^(NSURL *extractPath) {
      return [FBApplicationBundle findAppPathFromDirectory:extractPath];
    }];
}

+ (FBFuture<FBApplicationBundle *> *)findAppPathFromDirectory:(NSURL *)directory
{
  NSDirectoryEnumerator *directoryEnumerator = [NSFileManager.defaultManager
    enumeratorAtURL:directory
    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
    options:0
    errorHandler:nil];
  NSSet *applicationURLs = [NSSet set];
  for (NSURL *fileURL in directoryEnumerator) {
    if ([FBApplicationBundle isApplicationAtPath:fileURL.path]) {
      applicationURLs = [applicationURLs setByAddingObject:fileURL];
      [directoryEnumerator skipDescendants];
    }
  }
  if (applicationURLs.count != 1) {
    return [[FBControlCoreError
      describeFormat:@"Expected only one Application in IPA, found %lu", applicationURLs.count]
      failFuture];
  }
  return [self extractedApplicationAtPath:[applicationURLs.allObjects.firstObject path] directory:directory];
}

+ (NSString *)copyFrameworkToApplicationAtPath:(NSString *)appPath frameworkPath:(NSString *)frameworkPath
{
  if (![FBApplicationBundle isApplicationAtPath:appPath]) {
    return nil;
  }

  NSError *error = nil;
  NSFileManager *fileManager= [NSFileManager defaultManager];

  NSString *frameworksDir = [appPath stringByAppendingPathComponent:@"Frameworks"];
  BOOL isDirectory = NO;
  if ([fileManager fileExistsAtPath:frameworksDir isDirectory:&isDirectory]) {
    if (!isDirectory) {
      return [[FBControlCoreError
        describeFormat:@"%@ is not a directory", frameworksDir]
        fail:nil];
    }
  } else {
    if (![fileManager createDirectoryAtPath:frameworksDir withIntermediateDirectories:NO attributes:nil error:&error]) {
      return [[FBControlCoreError
        describeFormat:@"Create framework directory %@ failed", frameworksDir]
        fail:&error];
    }
  }

  NSString *toPath = [frameworksDir stringByAppendingPathComponent:[frameworkPath lastPathComponent]];
  if ([[NSFileManager defaultManager] fileExistsAtPath:toPath]) {
    return appPath;
  }

  if (![fileManager copyItemAtPath:frameworkPath toPath:toPath  error:&error]) {
    return [[FBControlCoreError
      describeFormat:@"Error copying framework %@ to app %@.", frameworkPath, appPath]
      fail:&error];
  }

  return appPath;
}

+ (BOOL)isApplicationAtPath:(NSString *)path
{
  BOOL isDirectory = NO;
  return path != nil
    && [path hasSuffix:@".app"]
    && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]
    && isDirectory;
}

#pragma mark Private

+ (FBFutureContext<NSURL *> *)temporaryExtractPathWithQueue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSURL *temporaryPath = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSProcessInfo.processInfo.globallyUniqueString] isDirectory:YES];
  return [[FBFuture
    onQueue:queue resolve:^{
      NSError *error = nil;
      if (![NSFileManager.defaultManager createDirectoryAtURL:temporaryPath withIntermediateDirectories:YES attributes:nil error:&error]) {
        return [[[FBControlCoreError
          describeFormat:@"Could not create temporary directory for IPA extraction %@", temporaryPath]
          causedBy:error]
          failFuture];
      }
      return [FBFuture futureWithResult:temporaryPath];
    }]
    onQueue:queue contextualTeardown:^(NSString *extractPath, FBFutureState __) {
      [logger logFormat:@"Removing extracted directory %@", temporaryPath];
      NSError *innerError = nil;
      if ([NSFileManager.defaultManager removeItemAtPath:extractPath error:&innerError]) {
        [logger logFormat:@"Removed extracted directory %@", temporaryPath];
      } else {
        [logger logFormat:@"Failed to remove extracted directory %@ with error %@", temporaryPath, innerError];
      }
    }];
}

+ (FBFuture<FBApplicationBundle *> *)extractedApplicationAtPath:(NSString *)appPath directory:(NSURL *)directory
{
  NSError *error = nil;
  FBApplicationBundle *bundle = [FBApplicationBundle applicationWithPath:appPath error:&error];
  if (!bundle) {
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:bundle];
}

@end
