/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

