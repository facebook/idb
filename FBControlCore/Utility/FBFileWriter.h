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

/**
 Creates a File Writer that does not write anywhere.

 @return a File Reader.
 */
+ (instancetype)nullWriter;

/**
 Creates a File Writer from a File Handle.

 @param fileHandle the file handle to write to. It will be closed when an EOF is sent.
 @param blocking YES if the writer should block on the calling thread when writing, NO otherwise.
 @return a File Reader.
 */
+ (instancetype)writerWithFileHandle:(NSFileHandle *)fileHandle blocking:(BOOL)blocking;

/**
 Creates a File Writer from a File Path

 @param filePath the file handle to write to from. It will be closed when an EOF is sent.
 @param blocking YES if the writer should block on the calling thread when writing, NO otherwise.
 @param error an error out for any error that occurs.
 @return a File Reader on success, nil otherwise.
 */
+ (nullable instancetype)writerForFilePath:(NSString *)filePath blocking:(BOOL)blocking error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
