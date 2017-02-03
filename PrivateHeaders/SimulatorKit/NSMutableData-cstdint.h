/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/NSMutableData.h>

@interface NSMutableData (cstdint)
- (void)appendUInt64InBigEndian:(unsigned long long)arg1;
- (void)appendUInt32InBigEndian:(unsigned int)arg1;
- (void)appendUInt16InBigEndian:(unsigned short)arg1;
- (void)appendUInt8:(unsigned char)arg1;
@end
