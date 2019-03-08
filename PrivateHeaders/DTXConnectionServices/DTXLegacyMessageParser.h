/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

