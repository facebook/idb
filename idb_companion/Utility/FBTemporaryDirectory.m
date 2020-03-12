/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTemporaryDirectory.h"

#import "FBIDBError.h"
#import "FBStorageUtils.h"

@interface FBTemporaryDirectory ()

@property (nonatomic, copy, readonly) NSURL *rootTemporaryDirectory;

@end

@implementation FBTemporaryDirectory

+ (instancetype)temporaryDirectoryWithLogger:(id<FBControlCoreLogger>)logger
{
  NSArray<NSString *> *tempPathComponents = @[NSTemporaryDirectory(), @"IDB", [[NSUUID UUID] UUIDString]];
  NSURL *temporaryDirectory = [NSURL fileURLWithPathComponents:tempPathComponents];
  NSError *error;
  BOOL success = [NSFileManager.defaultManager createDirectoryAtURL:temporaryDirectory withIntermediateDirectories:YES attributes:nil error:&error];
  NSAssert(success, @"%@", error);
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.idb.fbtemporarydirectory", DISPATCH_QUEUE_SERIAL);
  return [[self alloc] initWithRootDirectory:temporaryDirectory queue:queue logger:logger];
}

- (instancetype)initWithRootDirectory:(NSURL *)rootDirectory queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _rootTemporaryDirectory = rootDirectory;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (void)cleanOnExit
{
  NSError *error;
  BOOL success = [NSFileManager.defaultManager removeItemAtURL:self.rootTemporaryDirectory error:&error];
  if (!success) {
    [self.logger.error logFormat:@"Couldn't remove temporary directory: %@ (%@)", self.rootTemporaryDirectory, error.localizedDescription];
  } else {
    [self.logger.debug logFormat:@"Successfully removed temporal directory: %@", self.rootTemporaryDirectory];
  }
}

- (NSURL *)ephemeralTemporaryDirectory
{
  return [self.rootTemporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
}

- (FBFutureContext<NSURL *> *)withGzipExtractedFromStream:(FBProcessInput *)input name:(NSString *)name
{
  return [[self
    withTemporaryFileNamed:name]
    onQueue:self.queue pend:^(NSURL *result) {
      return [[FBArchiveOperations
        extractGzipFromStream:input toPath:result.path queue:self.queue logger:self.logger]
        mapReplace:result];
    }];
}

- (FBFutureContext<NSURL *> *)withArchiveExtracted:(NSData *)tarData
{
  return [self withArchiveExtractedFromStream:[FBProcessInput inputFromData:tarData]];
}

- (FBFutureContext<NSURL *> *)withArchiveExtractedFromStream:(FBProcessInput *)input
{
  return [[self
    withTemporaryDirectory]
    onQueue:self.queue pend:^(NSURL *tempDir) {
      return [[FBArchiveOperations extractArchiveFromStream:input toPath:tempDir.path queue:self.queue logger:self.logger] mapReplace:tempDir];
    }];
}

- (FBFutureContext<NSURL *> *)withArchiveExtractedFromFile:(NSString *)filePath
{
  return [[self
    withTemporaryDirectory]
    onQueue:self.queue pend:^(NSURL *tempDir) {
      return [[FBArchiveOperations extractArchiveAtPath:filePath toPath:tempDir.path queue:self.queue logger:self.logger] mapReplace:tempDir];
    }];
}

- (FBFutureContext<NSArray<NSURL *> *> *)withFilesInTar:(NSData *)tarData orFilePaths:(nullable NSArray<NSString *> *)filePaths
{
  if (filePaths){
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:filePaths.count];
    for (NSString *filePath in filePaths) {
      [urls addObject:[NSURL fileURLWithPath:filePath]];
    }
    return [FBFutureContext futureContextWithResult:urls];
  }

  return [self filesFromSubdirs:[self withArchiveExtracted:tarData]];
}

- (FBFutureContext<NSArray<NSURL *> *> *)filesFromSubdirs:(FBFutureContext<NSURL *> *)extractionDirContext
{
  return [extractionDirContext
    onQueue:self.queue pend:^ FBFuture<NSArray<NSURL *> *> * (NSURL *extractionDir) {
      NSError *error = nil;
      NSArray<NSURL *> *subfolders = [FBStorageUtils filesInDirectory:extractionDir error:&error];
      if (!subfolders) {
        return [FBFuture futureWithError:error];
      }
      NSMutableArray<NSURL *> *filesInTar = [NSMutableArray arrayWithCapacity:subfolders.count];
      for (NSURL *subfolder in subfolders) {
        NSURL *file = [FBStorageUtils findUniqueFileInDirectory:subfolder error:&error];
        if (!file) {
          return [FBFuture futureWithError:error];
        }
        [filesInTar addObject:file];
      }
      return [FBFuture futureWithResult:filesInTar];
    }];
}

#pragma mark Temporary Directory

- (NSURL *)temporaryDirectory
{
  NSURL *tempDirectory = self.ephemeralTemporaryDirectory;
  [self.logger logFormat:@"Creating Temp Dir %@", tempDirectory];
  NSError *error = nil;
  if (![NSFileManager.defaultManager createDirectoryAtURL:tempDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
    [self.logger logFormat:@"Failed to create Temp Dir %@ with error %@", tempDirectory, error];
  }
  return tempDirectory;
}

- (FBFutureContext<NSURL *> *)withTemporaryDirectory
{
  NSURL *tempDirectory = self.ephemeralTemporaryDirectory;
  [self.logger logFormat:@"Creating Temp Dir %@", tempDirectory];
  NSError *error = nil;
  if (![NSFileManager.defaultManager createDirectoryAtURL:tempDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
    return [[[FBIDBError
      describeFormat:@"Failed to create Temp Dir %@", tempDirectory]
      causedBy:error]
      failFutureContext];
  }
  return [[FBFuture
    futureWithResult:tempDirectory]
    onQueue:self.queue contextualTeardown:^(id _, FBFutureState __) {
      NSError *innerError = nil;
      if ([NSFileManager.defaultManager removeItemAtURL:tempDirectory error:&innerError]) {
        [self.logger logFormat:@"Deleted Temp Dir %@", tempDirectory];
      } else {
        [self.logger logFormat:@"Failed to delete Temp Dir %@: %@", tempDirectory, innerError];
      }
      return FBFuture.empty;
    }];
}

- (FBFutureContext<NSURL *> *)withTemporaryFileNamed:(NSString *)name
{
  return [[[self
    withTemporaryDirectory]
    onQueue:self.queue pend:^(NSURL *directory) {
      NSURL *tempFile = [directory URLByAppendingPathComponent:name];
      return [FBFuture futureWithResult:tempFile];
    }]
    onQueue:self.queue contextualTeardown:^(NSURL *tempFile, FBFutureState __) {
      NSError *innerError = nil;
      if ([NSFileManager.defaultManager removeItemAtURL:tempFile error:&innerError]) {
        [self.logger logFormat:@"Deleted Temp File %@", tempFile];
      } else {
        [self.logger logFormat:@"Failed to delete Temp File %@: %@", tempFile, innerError];
      }
      return FBFuture.empty;
    }];
}

@end
