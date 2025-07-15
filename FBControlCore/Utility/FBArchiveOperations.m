/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBArchiveOperations.h"

#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBProcess.h"
#import "FBProcessBuilder.h"

NSString *const BSDTarPath = @"/usr/bin/bsdtar";

@implementation FBArchiveOperations

+ (FBFuture<NSString *> *)extractArchiveAtPath:(NSString *)path toPath:(NSString *)extractPath overrideModificationTime:(BOOL)overrideMTime logger:(id<FBControlCoreLogger>)logger
{
  return [[[[[[[FBProcessBuilder
    withLaunchPath:BSDTarPath]
    withArguments:@[overrideMTime ? @"-zxpm" : @"-zxp", @"-C", extractPath, @"-f", path]]
    withStdErrToLoggerAndErrorMessage:logger.debug]
    withStdOutToLogger:logger.debug]
    withTaskLifecycleLoggingTo:logger]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    mapReplace:extractPath];
}

+ (NSArray<NSString *> *)commandToExtractFromStdInWithExtractPath:(NSString *)extractPath overrideModificationTime:(BOOL)overrideMTime compression:(FBCompressionFormat)compression
{
  NSArray<NSString *> *extractCommand = @[overrideMTime ? @"-zxpm" : @"-zxp", @"-C", extractPath, @"-f", @"-"];
  if (compression == FBCompressionFormatZSTD) {
    extractCommand = @[@"--use-compress-program", @"pzstd -d", overrideMTime ? @"-xpm" : @"-xp", @"-C", extractPath, @"-f", @"-"];
  }
  return extractCommand;
}

+ (FBFuture<NSString *> *)extractArchiveFromStream:(FBProcessInput *)stream toPath:(NSString *)extractPath overrideModificationTime:(BOOL)overrideMTime logger:(id<FBControlCoreLogger>)logger compression:(FBCompressionFormat)compression
{
  return [[[[[[[[FBProcessBuilder
    withLaunchPath:BSDTarPath]
    withArguments:[self commandToExtractFromStdInWithExtractPath:extractPath overrideModificationTime:overrideMTime compression:compression]]
    withStdIn:stream]
    withStdErrToLoggerAndErrorMessage:logger.debug]
    withStdOutToLogger:logger.debug]
    withTaskLifecycleLoggingTo:logger]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    mapReplace:extractPath];
}

+ (FBFuture<NSString *> *)extractGzipFromStream:(FBProcessInput *)stream toPath:(NSString *)extractPath logger:(id<FBControlCoreLogger>)logger
{
  return [[[[[[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/gunzip"]
    withArguments:@[@"--to-stdout"]]
    withStdIn:stream]
    withStdErrToLoggerAndErrorMessage:logger.debug]
    withStdOutPath:extractPath]
    withTaskLifecycleLoggingTo:logger]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    mapReplace:extractPath];
}

+ (FBFuture<FBProcess<NSNull *, NSInputStream *, id> *> *)createGzipForPath:(NSString *)path logger:(id<FBControlCoreLogger>)logger
{
  return (FBFuture<FBProcess<NSNull *, NSInputStream *, id> *> *) [[[[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/gzip"]
    withArguments:@[@"--to-stdout", path]]
    withStdErrToLoggerAndErrorMessage:logger]
    withStdOutToInputStream]
    withTaskLifecycleLoggingTo:logger]
    start];
}


+ (FBFuture<FBProcess<id, NSData *, id> *> *)createGzipDataFromProcessInput:(FBProcessInput *)input logger:(id<FBControlCoreLogger>)logger
{
  return (FBFuture<FBProcess<id, NSData *, id> *> *) [[[[[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/gzip"]
    withArguments:@[@"-", @"--to-stdout"]]
    withStdIn:input]
    withStdErrToLoggerAndErrorMessage:logger]
    withStdOutInMemoryAsData]
    withTaskLifecycleLoggingTo:logger]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]
  ];
}


+ (FBFuture<FBProcess<NSNull *, NSInputStream *, id> *> *)createGzippedTarForPath:(NSString *)path logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  FBProcessBuilder<NSNull *, NSData *, id> *builder = [self createGzippedTarTaskBuilderForPath:path logger:logger error:&error];
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
  FBProcessBuilder<NSNull *, NSData *, id> *builder = [self createGzippedTarTaskBuilderForPath:path logger:logger error:&error];
  if (!builder) {
    return [FBFuture futureWithError:error];
  }
  return [[builder
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    onQueue:queue map:^(FBProcess<NSNull *, NSData *, id<FBControlCoreLogger>> *result) {
      return [result stdOut];
    }];
}

#pragma mark Private

+ (FBProcessBuilder<NSNull *, NSData *, id> *)createGzippedTarTaskBuilderForPath:(NSString *)path logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
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

  return (FBProcessBuilder<NSNull *, NSData *, id> *) [[[[[FBProcessBuilder
    withLaunchPath:BSDTarPath]
    withArguments:@[@"-zvc", @"-f", @"-", @"-C", directory, fileName]]
    withStdOutInMemoryAsData]
    withStdErrToLoggerAndErrorMessage:logger]
    withTaskLifecycleLoggingTo:logger];
}

@end
