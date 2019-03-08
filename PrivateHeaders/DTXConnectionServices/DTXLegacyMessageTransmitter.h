/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <DTXConnectionServices/DTXMessageTransmitter.h>

@interface DTXLegacyMessageTransmitter : DTXMessageTransmitter
{
}

- (void)transmitMessage:(id)arg1 routingInfo:(struct DTXMessageRoutingInfo)arg2 fragment:(unsigned int)arg3 transmitter:(CDUnknownBlockType)arg4;
- (unsigned int)fragmentsForLength:(unsigned long long)arg1;

@end

