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

@implementation FBExtractedApplication

- (instancetype)initWithBundle:(FBApplicationBundle *)bundle extractedPath:(NSURL *)extractedPath
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _bundle = bundle;
  _extractedPath = extractedPath;

  return self;
}

@end

static BOOL deleteDirectory(NSURL *path)
{
  if (path == nil) {
    return YES;
  }
  return [[NSFileManager defaultManager] removeItemAtURL:path error:nil];
}

@implementation FBApplicationBundle (Install)

#pragma mark Public

+ (FBFutureContext<FBExtractedApplication *> *)onQueue:(dispatch_queue_t)queue findOrExtractApplicationAtPath:(NSString *)path logger:(id<FBControlCoreLogger>)logger;
{
  NSURL *extractPath = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSProcessInfo.processInfo.globallyUniqueString] isDirectory:YES];
  return [[FBApplicationBundle
    findOrExtractApplicationAtPath:path extractPath:extractPath queue:queue logger:logger]
    onQueue:queue pend:^(NSString *appPath) {
      NSError *error = nil;
      FBApplicationBundle *bundle = [FBApplicationBundle applicationWithPath:appPath error:&error];
      if (!bundle) {
        return [FBFuture futureWithError:error];
      }
      FBExtractedApplication *application = [[FBExtractedApplication alloc] initWithBundle:bundle extractedPath:extractPath];
      return [FBFuture futureWithResult:application];
  }];
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

+ (FBFutureContext<NSString *> *)findOrExtractApplicationAtPath:(NSString *)path extractPath:(NSURL *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  // If it's an App, we don't need to do anything, just return early.
  if ([FBApplicationBundle isApplicationAtPath:path]) {
    return [FBFutureContext futureContextWithResult:path];
  }
  // The other case is that this is an IPA, check it is before extacting.
  NSError *error = nil;
  if ([FBArchiveOperations headerMagicForFile:path] != FBFileHeaderMagicIPA) {
    return [[[FBControlCoreError
      describeFormat:@"File at path %@ is neither an IPA nor an .app", path]
      causedBy:error]
      failFutureContext];
  }
  // Create the path to extract into, if it doesn't exist yet.
  if (![NSFileManager.defaultManager createDirectoryAtURL:extractPath withIntermediateDirectories:YES attributes:nil error:&error]) {
    return [[[FBControlCoreError
      describeFormat:@"Could not create temporary directory for IPA extraction %@", extractPath]
      causedBy:error]
      failFutureContext];
  }
  return [[FBArchiveOperations
    extractZipArchiveAtPath:path toPath:extractPath.path queue:queue logger:logger]
    onQueue:queue pend:^(id _) {
      return [FBApplicationBundle findAppPathFromDirectory:extractPath];
    }];
}

+ (FBFuture<NSString *> *)findAppPathFromDirectory:(NSURL *)directory
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
    deleteDirectory(directory);
    return [[FBControlCoreError
      describeFormat:@"Expected only one Application in IPA, found %lu", applicationURLs.count]
      failFuture];
  }
  return [FBFuture futureWithResult:[applicationURLs.allObjects.firstObject path]];
}

@end
