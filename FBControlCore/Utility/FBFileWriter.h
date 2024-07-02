/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDataConsumer.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Data Consumer that writes out to a file or file descriptor.
 The dual of FBFileReader.
 Unlike FBFileReader, once initialized, there doesn't need to be an additional call to start writing.
 */
@interface FBFileWriter : NSObject

#pragma mark Initializers

/**
 Creates a File Writer that does not write anywhere.

 @return a File Reader.
 */
@property (nonatomic, strong, readonly, class) id<FBDataConsumer> nullWriter;

/**
 Creates a synchronous data consumer from a file handle.

 @param fileDescriptor the file descriptor to write to.
 @param closeOnEndOfFile YES if the file descriptor should be closed on consumeEndOfFile, NO otherwise.
 @return a data consumer.
 */
+ (id<FBDataConsumer, FBDataConsumerLifecycle, FBDataConsumerSync>)syncWriterWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile;

/**
 Creates a non-blocking Data Consumer from a file handle.
 The file handle will be closed when and end-of-file is sent.

 @param fileDescriptor the file descriptor to write to.
 @param closeOnEndOfFile YES if the file descriptor should be closed on consumeEndOfFile, NO otherwise.
 @return a data consumer.
 */
+ (nullable id<FBDataConsumer, FBDataConsumerLifecycle>)asyncWriterWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile error:(NSError **)error;

/**
 Creates a non-blocking Dispatch Data Consumer from a file Handle.

 @param fileDescriptor the file descriptor to write to.
 @param closeOnEndOfFile YES if the file descriptor should be closed on consumeEndOfFile, NO otherwise.
 @return a Future wrapping the Data Consumer.
 */
+ (FBFuture<id<FBDispatchDataConsumer>> *)asyncDispatchDataWriterWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile;

/**
 Creates a blocking Data Consumer from a file path.
 The file handle backing this path will be closed when and end-of-file is sent.

 @param filePath the file handle to write to from.
 @param error an error out for any error that occurs.
 @return a data consumer on success, nil otherwise.
 */
+ (nullable id<FBDataConsumer, FBDataConsumerLifecycle, FBDataConsumerSync>)syncWriterForFilePath:(NSString *)filePath error:(NSError **)error;

/**
 Creates a non-blocking Data Consumer from a file path.
 The file path will be opened asynchronously so that the caller is not blocked on opening a file handle for the path.
 The file handle backing this path will be closed when and end-of-file is sent.

 @param filePath the file handle to write to from.
 @return a future that resolves with the data consumer.
 */
+ (FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *)asyncWriterForFilePath:(NSString *)filePath;

@end

NS_ASSUME_NONNULL_END
