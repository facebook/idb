/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "NSObject.h"

@interface DTXMessageParsingBuffer : NSObject
{
    void *_buffer;
    unsigned long long _filled;
    unsigned long long _size;
}

- (unsigned long long)length;
- (const void *)buffer;
- (void)clear;
- (void)appendBytes:(const void *)arg1 ofLength:(unsigned long long)arg2;
- (void)dealloc;
- (id)initWithSize:(unsigned long long)arg1;

@end

