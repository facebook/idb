/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBArchiveOperations.h"

#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBTask.h"
#import "FBTaskBuilder.h"

@implementation FBArchiveOperations

+ (FBFuture<NSString *> *)extractArchiveAtPath:(NSString *)path toPath:(NSString *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  FBFileHeaderMagic magic = [self headerMagicForFile:path];
  switch (magic) {
    case FBFileHeaderMagicIPA:
      return [self extractZipArchiveAtPath:path toPath:extractPath queue:queue logger:logger];
    case FBFileHeaderMagicGZIP:
      return [self extractTarArchiveAtPath:path toPath:extractPath queue:queue logger:logger];
    default:
      return [[FBControlCoreError
        describeFormat:@"File at path %@ is not determined to be an archive", path]
        failFuture];
  }
}

+ (FBFuture<NSString *> *)extractZipArchiveAtPath:(NSString *)path toPath:(NSString *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/unzip"]
    withArguments:@[@"-o", @"-d", extractPath, path]]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@0]]
    withStdErrToLogger:logger.debug]
    withStdOutToLogger:logger.debug]
    runUntilCompletion]
    mapReplace:extractPath];
}

+ (FBFuture<NSString *> *)extractTarArchiveAtPath:(NSString *)path toPath:(NSString *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/tar"]
    withArguments:@[@"-C", extractPath, @"-vzxpf", path]]
    withStdErrToLogger:logger.debug]
    withStdOutToLogger:logger.debug]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@0]]
    runUntilCompletion]
    mapReplace:extractPath];
}

+ (FBFuture<NSString *> *)extractTarArchiveFromStream:(FBProcessInput *)stream toPath:(NSString *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[[[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/tar"]
    withArguments:@[@"-C", extractPath, @"-vzxpf", @"-"]]
    withStdIn:stream]
    withStdErrToLogger:logger.debug]
    withStdOutToLogger:logger.debug]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@0]]
    runUntilCompletion]
    mapReplace:extractPath];
}

+ (FBFuture<NSString *> *)extractGzipFromStream:(FBProcessInput *)stream toPath:(NSString *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[[[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/gunzip"]
    withArguments:@[@"-v", @"--to-stdout"]]
    withStdIn:stream]
    withStdErrToLogger:logger.debug]
    withStdOutPath:extractPath]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@0]]
    runUntilCompletion]
    mapReplace:extractPath];
}

+ (FBFuture<FBTask<NSNull *, NSInputStream *, id<FBControlCoreLogger>> *> *)createGzipForPath:(NSString *)path queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/gzip"]
    withArguments:@[@"--to-stdout", @"--verbose", path]]
    withStdErrToLogger:logger]
    withStdOutToInputStream]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@0]]
    start];
}

+ (FBFuture<FBTask<NSNull *, NSInputStream *, id<FBControlCoreLogger>> *> *)createGzippedTarForPath:(NSString *)path queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  FBTaskBuilder<NSNull *, NSData *, id<FBControlCoreLogger>> *builder = [self createGzippedTarTaskBuilderForPath:path queue:queue logger:logger error:&error];
  if (!builder) {
    return [FBFuture futureWithError:error];
  }
  return [[builder
    withStdOutToInputStream]
    start];
}

+ (FBFuture<NSData *> *)createGzippedTarDataForPath:(NSString *)path queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  FBTaskBuilder<NSNull *, NSData *, id<FBControlCoreLogger>> *builder = [self createGzippedTarTaskBuilderForPath:path queue:queue logger:logger error:&error];
  if (!builder) {
    return [FBFuture futureWithError:error];
  }
  return [[builder
    runUntilCompletion]
    onQueue:queue map:^(FBTask<NSNull *, NSData *, id<FBControlCoreLogger>> *result) {
      return [result stdOut];
    }];
}


// The Magic Header for Zip Files is two chars 'PK'. As a short this is as below.
static unsigned short const ZipFileMagicHeader = 0x4b50;
// The Magic Header for Tar Files
static unsigned short const TarFileMagicHeader = 0x8b1f;

+ (FBFileHeaderMagic)headerMagicForData:(NSData *)data
{
  unsigned short magic = 0;
  [data getBytes:&magic length:sizeof(short)];
  return [self magicForShort:magic];
}

+ (FBFileHeaderMagic)headerMagicForFile:(NSString *)path
{
  // IPAs are Zip files. Zip Files always have a magic header in their first 4 bytes.
  FILE *file = fopen(path.UTF8String, "r");
  if (!file) {
    return FBFileHeaderMagicUnknown;
  }
  unsigned short magic = 0;
  if (!fread(&magic, sizeof(short), 1, file)) {
    fclose(file);
    return FBFileHeaderMagicUnknown;
  }
  fclose(file);
  return [self magicForShort:magic];
}

#pragma mark Private

+ (FBFileHeaderMagic)magicForShort:(unsigned short)magic
{
  if (magic == ZipFileMagicHeader) {
    return FBFileHeaderMagicIPA;
  } else if (magic == TarFileMagicHeader) {
    return FBFileHeaderMagicGZIP;
  }
  return FBFileHeaderMagicUnknown;
}

+ (FBTaskBuilder<NSNull *, NSData *, id<FBControlCoreLogger>> *)createGzippedTarTaskBuilderForPath:(NSString *)path queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  BOOL isDirectory;
  if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory]) {
    return [[FBControlCoreError
      describeFormat:@"Path for tarring %@ doesn't exist", path]
      fail:error];
  }

  NSString *directory;
  NSString *fileName;
  if (isDirectory) {
    directory = path;
    fileName = @".";
    [logger.info logFormat:@"%@ is a directory, tarring with it as the root.", directory];
    if ([[NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil] count] < 1) {
      [logger.info logFormat:@"Attempting to tar directory at path %@, but it has no contents", path];
    }
  } else {
    directory = path.stringByDeletingLastPathComponent;
    fileName = path.lastPathComponent;
    [logger.info logFormat:@"%@ is a file, tarring relative to it's parent %@", path, directory];
    NSDictionary<NSString *, id> *fileAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    NSUInteger fileSize = [fileAttributes[NSFileSize] unsignedIntegerValue];
    if (fileSize <= 0) {
      [logger.info logFormat:@"Attempting to tar file at path %@, but it has no content", path];
    }
  }

  return [[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/tar"]
    withArguments:@[@"-zvcf", @"-", @"-C", directory, fileName]]
    withStdOutInMemoryAsData]
    withStdErrToLogger:logger]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@0]];
}

@end
