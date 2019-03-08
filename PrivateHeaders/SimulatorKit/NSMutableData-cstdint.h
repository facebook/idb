/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSMutableData.h>

@interface NSMutableData (cstdint)
- (void)appendUInt64InBigEndian:(unsigned long long)arg1;
- (void)appendUInt32InBigEndian:(unsigned int)arg1;
- (void)appendUInt16InBigEndian:(unsigned short)arg1;
- (void)appendUInt8:(unsigned char)arg1;
@end
