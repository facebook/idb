/**
 * Copyright (c) Facebook, Inc. and its affiliates.
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
 Unlike FBFileReader, once initialized, this writer is ready to consume data.
 */
@interface FBFileWriter : NSObject

#pragma mark Initializers

/**
 Creates a File Writer that does not write anywhere.

 @return a File Reader.
 */
@property (nonatomic, strong, readonly, class) id<FBDataConsumer> nullWriter;

/**
 Creates a blocking data consumer from a file handle.
 The file handle will be closed when and end-of-file is sent.

 @param fileHandle the file handle to write to.
 @return a data consumer.
 */
+ (id<FBDataConsumer, FBDataConsumerLifecycle>)syncWriterWithFileHandle:(NSFileHandle *)fileHandle;

/**
 Creates a non-blocking Data Consumer from a file handle.
 The file handle will be closed when and end-of-file is sent.

 @param fileHandle the file handle to write to.
 @return a data consumer.
 */
+ (nullable id<FBDataConsumer, FBDataConsumerLifecycle>)asyncWriterWithFileHandle:(NSFileHandle *)fileHandle error:(NSError **)error;

/**
 Creates a non-blocking Dispatch Data Consumer from a file Handle.

 @param fileHandle the file handle to write to. It will be closed when an EOF is sent.
 @return a Future wrapping the Data Consumer.
 */
+ (FBFuture<id<FBDispatchDataConsumer>> *)asyncDispatchDataWriterWithFileHandle:(NSFileHandle *)fileHandle;

/**
 Creates a blocking Data Consumer from a file path.
 The file handle backing this path will be closed when and end-of-file is sent.

 @param filePath the file handle to write to from.
 @param error an error out for any error that occurs.
 @return a data consumer on success, nil otherwise.
 */
+ (nullable id<FBDataConsumer, FBDataConsumerLifecycle>)syncWriterForFilePath:(NSString *)filePath error:(NSError **)error;

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
