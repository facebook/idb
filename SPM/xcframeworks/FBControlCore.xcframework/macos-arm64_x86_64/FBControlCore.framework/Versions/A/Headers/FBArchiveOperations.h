/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBSubprocess.h>

extern NSString * _Nonnull const BSDTarPath;

/**
 An enum representing the compression types available.
 */
typedef NS_ENUM(NSUInteger, FBCompressionFormat) {
  FBCompressionFormatGZIP = 1,
  FBCompressionFormatZSTD = 2,
};

@class FBProcessInput;

/**
 Operations of Zip/Tar Archives
 */
@interface FBArchiveOperations : NSObject

/**
 Builds a command to extract from a file on disk

 @param path the path to the archive.
 @param extractPath the extraction path.
 @param overrideMTime if YES the archive contests' `mtime` will be ignored. Current timestamp will be used as mtime of extracted files/directories.
 @return an array of strings for the command to invoke.
 */
+ (nonnull NSArray<NSString *> *)commandToExtractArchiveAtPath:(nonnull NSString *)path toPath:(nonnull NSString *)extractPath overrideModificationTime:(BOOL)overrideMTime debugLogging:(BOOL)debugLogging;

/**
 Extracts a tar, or zip file archive to a directory.
 The file can be a:
 - An uncompressed tar.
 - A gzipped tar.
 - A zip.

 @param path the path to the archive.
 @param extractPath the extraction path.
 @param overrideMTime if YES the archive contests' `mtime` will be ignored. Current timestamp will be used as mtime of extracted files/directories.
 @param logger the logger to log to.
 @return a Future wrapping the extracted tar destination.
 */
+ (nonnull FBFuture<NSString *> *)extractArchiveAtPath:(nonnull NSString *)path toPath:(nonnull NSString *)extractPath overrideModificationTime:(BOOL)overrideMTime logger:(nonnull id<FBControlCoreLogger>)logger;

/**
 Builds a command to extract via stdin

 @param extractPath the extraction path
 @param overrideMTime if YES the archive contests' `mtime` will be ignored. Current timestamp will be used as mtime of extracted files/directories.
 @param compression compression format used by client
 @param debugLogging whether to apply debug logging in the command.
 @return an array of strings for the command to invoke.
 */
+ (nonnull NSArray<NSString *> *)commandToExtractFromStdInWithExtractPath:(nonnull NSString *)extractPath overrideModificationTime:(BOOL)overrideMTime compression:(FBCompressionFormat)compression debugLogging:(BOOL)debugLogging;

/**
 Extracts a tar, or zip stream archive to a directory.
 The stream can be a:
 - An uncompressed tar.
 - A gzipped tar.
 - A zstd compressed tar
 - A zip.

 @param stream the stream of the archive.
 @param extractPath the extraction path
 @param overrideMTime if YES the archive contests' `mtime` will be ignored. Current timestamp will be used as mtime of extracted files/directories.
 @param logger the logger to log to
 @param compression compression format used by client
 @return a Future wrapping the extracted tar destination.
 */
+ (nonnull FBFuture<NSString *> *)extractArchiveFromStream:(nonnull FBProcessInput *)stream toPath:(nonnull NSString *)extractPath overrideModificationTime:(BOOL)overrideMTime logger:(nonnull id<FBControlCoreLogger>)logger compression:(FBCompressionFormat)compression;

/**
 Extracts a gzip from a stream to a single file.
 A plain gzip wrapping a single file is preferred when there's only a single file to transfer.

 @param stream the stream of the gzip archive.
 @param extractPath the extraction path.
 @param logger the logger to log to
 @return a Future wrapping the extracted tar destination.
 */
+ (nonnull FBFuture<NSString *> *)extractGzipFromStream:(nonnull FBProcessInput *)stream toPath:(nonnull NSString *)extractPath logger:(nonnull id<FBControlCoreLogger>)logger;

/**
 Creates a gzipped archive compressing the data provided.

 @param input the data to be compressed.
 @param logger the logger to log to.
 @return a Future wrapping the archive data.
 */
+ (nonnull FBFuture<FBSubprocess<id, NSData *, id> *> *)createGzipDataFromProcessInput:(nonnull FBProcessInput *)input logger:(nonnull id<FBControlCoreLogger>)logger;

/**
 Creates a gzips archive, returning an task that has an NSInputStream attached to stdout.
 A plain gzip wrapping a single file is preferred when there's only a single file to transfer.
 Read the input stream to obtain all of the gzip output of the file.
 To confirm that the stream has been correctly written, the caller should check the exit code of the returned task upon completion.

 @param path the path to archive.
 @param logger the logger to log to.
 @return a Future containing a task with an NSInputStream attached to stdout.
 */
+ (nonnull FBFuture<FBSubprocess<NSNull *, NSInputStream *, id> *> *)createGzipForPath:(nonnull NSString *)path logger:(nonnull id<FBControlCoreLogger>)logger;

/**
 Creates a gzipped tar archive, returning an task that has an NSInputStream attached to stdout.
 Read the input stream to obtain the gzipped tar output.
 To confirm that the stream has been correctly written, the caller should check the exit code of the returned task upon completion.

 @param path the path to archive.
 @param logger the logger to log to.
 @return a Future containing a task with an NSInputStream attached to stdout.
 */
+ (nonnull FBFuture<FBSubprocess<NSNull *, NSInputStream *, id> *> *)createGzippedTarForPath:(nonnull NSString *)path logger:(nonnull id<FBControlCoreLogger>)logger;

/**
 Creates a gzipped tar archive, returning an the data of the tar.

 @param path the path to archive.
 @param queue the queue to do work on
 @param logger the logger to log to.
 @return a Future containing the tar output.
 */
+ (nonnull FBFuture<NSData *> *)createGzippedTarDataForPath:(nonnull NSString *)path queue:(nonnull dispatch_queue_t)queue logger:(nonnull id<FBControlCoreLogger>)logger;

@end
