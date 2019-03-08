/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSString.h>

@interface NSString (SIMPackedVersion)
+ (id)sim_stringForPackedVersion:(unsigned int)arg1;
- (unsigned int)sim_packedVersion;
@end
