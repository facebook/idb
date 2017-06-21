/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An object for accumilating and buffering lines
 Writes and Reads will not be synchronized.
 */
@interface FBLineBuffer : NSObject

/**
 Appends the provided text data to the buffer.

 @param data the data to consume.
 */
- (void)appendData:(NSData *)data;

/**
 Consume the remainder of the buffer available, returning it as Data.
 This will flush the buffer.
 */
- (nullable NSData *)consumeCurrentData;

/**
 Consume a line if one is available, returning it as Data.
 This will flush the buffer of the lines that are consumed.
 */
- (nullable NSData *)consumeLineData;

/**
 Consume a line if one is available, returning it as a String.
 This will flush the buffer of the lines that are consumed.
 */
- (nullable NSString *)consumeLineString;

@end

NS_ASSUME_NONNULL_END
