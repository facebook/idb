/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
 Creates a blocking Data Consumer from a file handle.

 @param fileHandle the file handle to write to. It will be closed when an EOF is sent.
 @return a Data Consumer.
 */
+ (id<FBDataConsumer>)syncWriterWithFileHandle:(NSFileHandle *)fileHandle;

/**
 Creates a non-blocking Data Consumer from a file Handle.

 @param fileHandle the file handle to write to. It will be closed when an EOF is sent.
 @return a Data Consumer.
 */
+ (nullable id<FBDataConsumer>)asyncWriterWithFileHandle:(NSFileHandle *)fileHandle error:(NSError **)error;

/**
 Creates a non-blocking Dispatch Data Consumer from a file Handle.

 @param fileHandle the file handle to write to. It will be closed when an EOF is sent.
 @return a Future wrapping the Data Consumer.
 */
+ (FBFuture<id<FBDispatchDataConsumer>> *)asyncDispatchDataWriterWithFileHandle:(NSFileHandle *)fileHandle;

/**
 Creates a blocking Data Consumer from a file path.

 @param filePath the file handle to write to from. It will be closed when an EOF is sent.
 @param error an error out for any error that occurs.
 @return a Data Consumer on success, nil otherwise.
 */
+ (nullable id<FBDataConsumer>)syncWriterForFilePath:(NSString *)filePath error:(NSError **)error;

/**
 Creates a non-blocking Data Consumer from a file path.
 The File Path will be opened asynchronously so that the caller is not blocked.

 @param filePath the file handle to write to from. It will be closed when an EOF is sent.
 @return a Future that resolves with the Data Consumer.
 */
+ (FBFuture<id<FBDataConsumer>> *)asyncWriterForFilePath:(NSString *)filePath;

@end

NS_ASSUME_NONNULL_END
