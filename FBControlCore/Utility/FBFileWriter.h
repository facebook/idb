/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFileConsumer.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A File Data Consumer that writes to a file handle.
 Writes are non-blocking.
 */
@interface FBFileWriter : NSObject <FBFileConsumer>

#pragma mark Initializers

/**
 Creates a File Writer that does not write anywhere.

 @return a File Reader.
 */
@property (nonatomic, strong, readonly, class) FBFileWriter *nullWriter;

/**
 Creates a Blocking Writer from a File Handle.

 @param fileHandle the file handle to write to. It will be closed when an EOF is sent.
 @return a File Reader.
 */
+ (instancetype)syncWriterWithFileHandle:(NSFileHandle *)fileHandle;

/**
 Creates a Non-Blocking Writer from a File Handle.

 @param fileHandle the file handle to write to. It will be closed when an EOF is sent.
 @return a File Reader.
 */
+ (nullable instancetype)asyncWriterWithFileHandle:(NSFileHandle *)fileHandle error:(NSError **)error;

/**
 Creates a Blocking File Writer from a File Path

 @param filePath the file handle to write to from. It will be closed when an EOF is sent.
 @param error an error out for any error that occurs.
 @return a File Reader on success, nil otherwise.
 */
+ (nullable instancetype)syncWriterForFilePath:(NSString *)filePath error:(NSError **)error;

/**
 Creates a Non-Blocking File Writer from a File Path.
 The File Path will be opened asynchronously so that the caller is not blocked.

 @param filePath the file handle to write to from. It will be closed when an EOF is sent.
 @return a Future that resolves with the File Reader when reading has started.
 */
+ (FBFuture<FBFileWriter *> *)asyncWriterForFilePath:(NSString *)filePath;

@end

NS_ASSUME_NONNULL_END
