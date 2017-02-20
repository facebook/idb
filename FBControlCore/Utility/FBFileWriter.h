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
 Creates a File Writer from a File Handle.

 @param fileHandle the file handle to read from. It will be closed when the reader stops.
 @return a File Reader.
 */
+ (instancetype)writerWithFileHandle:(NSFileHandle *)fileHandle;

@end

NS_ASSUME_NONNULL_END
