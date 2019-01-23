/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationBundle+Install.h"

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

+ (FBFuture<FBExtractedApplication *> *)onQueue:(dispatch_queue_t)queue findOrExtractApplicationAtPath:(NSString *)path logger:(id<FBControlCoreLogger>)logger;
{
  NSURL *extractPath = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSProcessInfo.processInfo.globallyUniqueString] isDirectory:YES];
  return [[FBFuture
    onQueue:queue resolve:^{
      return [FBApplicationBundle findOrExtractApplicationAtPath:path extractPath:extractPath queue:queue logger:logger];
    }]
    onQueue:queue fmap:^(NSString *appPath) {
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

// The Magic Header for Zip Files is two chars 'PK'. As a short this is as below.
static unsigned short const ZipFileMagicHeader = 0x4b50;
// The Magic Header for Tar Files
static unsigned short const TarFileMagicHeader = 0x8b1f;

+ (FBFileHeaderMagic)headerMagicForData:(NSData *)data
{
  unsigned short magic = 0;
  [data getBytes:&magic length:sizeof(short)];
  if (magic == ZipFileMagicHeader) {
    return FBFileHeaderMagicIPA;
  } else if (magic == TarFileMagicHeader) {
    return FBFileHeaderMagicTAR;
  }
  return FBFileHeaderMagicUnknown;
}

#pragma mark Private

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

+ (FBFuture<NSString *> *)findOrExtractApplicationAtPath:(NSString *)path extractPath:(NSURL *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  // If it's an App, we don't need to do anything, just return early.
  if ([FBApplicationBundle isApplicationAtPath:path]) {
    return [FBFuture futureWithResult:path];
  }
  // The other case is that this is an IPA, check it is before extacting.
  NSError *error = nil;
  if (![FBApplicationBundle isIPAAtPath:path error:&error]) {
    return [[[FBControlCoreError
      describeFormat:@"File at path %@ is neither an IPA nor an .app", path]
      causedBy:error]
      failFuture];
  }
  // Create the path to extract into, if it doesn't exist yet.
  if (![NSFileManager.defaultManager createDirectoryAtURL:extractPath withIntermediateDirectories:YES attributes:nil error:&error]) {
    return [[[FBControlCoreError
      describeFormat:@"Could not create temporary directory for IPA extraction %@", extractPath]
      causedBy:error]
      failFuture];
  }
  // Run the unzip command.
  return [[[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/unzip"]
    withArguments:@[@"-o", @"-d", extractPath.path, path]]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@0]]
    withStdErrToLogger:logger.debug]
    withStdOutToLogger:logger.debug]
    runUntilCompletion]
    onQueue:queue fmap:^(FBTask *task) {
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
