/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <DTXConnectionServices/DTXMessageTransmitter.h>

@interface DTXLegacyMessageTransmitter : DTXMessageTransmitter
{
}

- (void)transmitMessage:(id)arg1 routingInfo:(void *)arg2 fragment:(unsigned int)arg3 transmitter:(CDUnknownBlockType)arg4;
- (unsigned int)fragmentsForLength:(unsigned long long)arg1;

@end

