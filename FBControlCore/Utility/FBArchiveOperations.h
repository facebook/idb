/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBTask.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessInput;

/**
 Operations of Zip/Tar Archives
 */
@interface FBArchiveOperations : NSObject

/**
 Extracts a tar, or zip file archive to a directory.
 The file can be a:
 - An uncompressed tar.
 - A gzipped tar.
 - A zip.

 @param path the path to the archive.
 @param extractPath the extraction path.
 @param queue the queue to do work on.
 @param logger the logger to log to.
 @return a Future wrapping the extracted tar destination.
 */
+ (FBFuture<NSString *> *)extractArchiveAtPath:(NSString *)path toPath:(NSString *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

/**
 Extracts a tar, or zip stream archive to a directory.
 The stream can be a:
 - An uncompressed tar.
 - A gzipped tar.
 - A zip.

 @param stream the stream of the archive.
 @param extractPath the extraction path
 @param queue the queue to do work on
 @param logger the logger to log to
 @return a Future wrapping the extracted tar destination.
 */
+ (FBFuture<NSString *> *)extractArchiveFromStream:(FBProcessInput *)stream toPath:(NSString *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

/**
 Extracts a gzip from a stream to a single file.
 A plain gzip wrapping a single file is preferred when there's only a single file to transfer.

 @param stream the stream of the gzip archive.
 @param extractPath the extraction path.
 @param queue the queue to do work on
 @param logger the logger to log to
 @return a Future wrapping the extracted tar destination.
 */
+ (FBFuture<NSString *> *)extractGzipFromStream:(FBProcessInput *)stream toPath:(NSString *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

/**
 Creates a gzips archive, returning an task that has an NSInputStream attached to stdout.
 A plain gzip wrapping a single file is preferred when there's only a single file to transfer.
 Read the input stream to obtain all of the gzip output of the file.

 @param path the path to archive.
 @param queue the queue to do work on
 @param logger the logger to log to.
 @return a A Future containing a task with an NSInputStream attached to stdout.
 */
+ (FBFuture<FBTask<NSNull *, NSInputStream *, id> *> *)createGzipForPath:(NSString *)path queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

/**
 Creates a gzipped tar archive, returning an task that has an NSInputStream attached to stdout.
 Read the input stream to obtain the gzipped tar output.

 @param path the path to archive.
 @param queue the queue to do work on
 @param logger the logger to log to.
 @return a A Future containing a task with an NSInputStream attached to stdout.
 */
+ (FBFuture<FBTask<NSNull *, NSInputStream *, id> *> *)createGzippedTarForPath:(NSString *)path queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

/**
 Creates a gzipped tar archive, returning an the data of the tar.

 @param path the path to archive.
 @param queue the queue to do work on
 @param logger the logger to log to.
 @return a A Future containing the tar output.
 */
+ (FBFuture<NSData *> *)createGzippedTarDataForPath:(NSString *)path queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
