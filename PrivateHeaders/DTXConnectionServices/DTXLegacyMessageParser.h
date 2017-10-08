/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <DTXConnectionServices/DTXMessageParser.h>

@class NSMutableArray;

@interface DTXLegacyMessageParser : DTXMessageParser
{
    NSMutableArray *_savedKeyArrays;
}

+ (void)initialize;
- (id)parseMessageWithExceptionHandler:(CDUnknownBlockType)arg1;
- (void)dealloc;
- (id)initWithMessageHandler:(CDUnknownBlockType)arg1 andParseExceptionHandler:(CDUnknownBlockType)arg2;

@end

