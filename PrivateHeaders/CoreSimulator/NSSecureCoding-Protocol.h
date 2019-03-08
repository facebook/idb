/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/NSCoding-Protocol.h>

@protocol NSSecureCoding <NSCoding>
+ (BOOL)supportsSecureCoding;
@end
