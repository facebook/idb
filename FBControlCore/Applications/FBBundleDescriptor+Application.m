/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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
#import "FBTask.h"
#import "FBTaskBuilder.h"

@implementation FBBundleDescriptor (Application)

#pragma mark Public

+ (FBFutureContext<FBBundleDescriptor *> *)onQueue:(dispatch_queue_t)queue findOrExtractApplicationAtPath:(NSString *)path  logger:(id<FBControlCoreLogger>)logger
{
  // If it's an App, we don't need to do anything, just return early.
  if ([FBBundleDescriptor isApplicationAtPath:path]) {
    return [FBFutureContext futureContextWithFuture:[self extractedApplicationAtPath:path directory:nil]];
  }
  return [[[self
    temporaryExtractPathWithQueue:queue logger:logger]
    onQueue:queue pend:^(NSURL *extractPath) {
      return [[FBArchiveOperations extractArchiveAtPath:path toPath:extractPath.path queue:queue logger:logger] mapReplace:extractPath];
    }]
    onQueue:queue pend:^(NSURL *extractPath) {
      return [FBBundleDescriptor findAppPathFromDirectory:extractPath];
    }];
}

+ (FBFutureContext<FBBundleDescriptor *> *)onQueue:(dispatch_queue_t)queue extractApplicationFromInput:(FBProcessInput *)input  logger:(id<FBControlCoreLogger>)logger
{
  return [[[self
    temporaryExtractPathWithQueue:queue logger:logger]
    onQueue:queue pend:^(NSURL *extractPath) {
      return [[FBArchiveOperations extractArchiveFromStream:input toPath:extractPath.path queue:queue logger:logger] mapReplace:extractPath];
    }]
    onQueue:queue pend:^(NSURL *extractPath) {
      return [FBBundleDescriptor findAppPathFromDirectory:extractPath];
    }];
}

+ (FBFuture<FBBundleDescriptor *> *)findAppPathFromDirectory:(NSURL *)directory
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
      failFuture];
  }
  return [self extractedApplicationAtPath:[applicationURLs.allObjects.firstObject path] directory:directory];
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
      return FBFuture.empty;
    }];
}

+ (FBFuture<FBBundleDescriptor *> *)extractedApplicationAtPath:(NSString *)appPath directory:(NSURL *)directory
{
  NSError *error = nil;
  FBBundleDescriptor *bundle = [FBBundleDescriptor bundleFromPath:appPath error:&error];
  if (!bundle) {
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:bundle];
}

@end
