/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSObject.h"

#import "NSCoding.h"

@interface DTXLegacyCompactDictionaryAdapter : NSObject <NSCoding>
{
}

- (id)initWithCoder:(id)arg1;
- (void)encodeWithCoder:(id)arg1;

@end

