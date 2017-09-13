/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <DTXConnectionServices/DTXMessageTransmitter.h>

@interface DTXLegacyMessageTransmitter : DTXMessageTransmitter
{
}

- (void)transmitMessage:(id)arg1 routingInfo:(struct DTXMessageRoutingInfo)arg2 fragment:(unsigned int)arg3 transmitter:(CDUnknownBlockType)arg4;
- (unsigned int)fragmentsForLength:(unsigned long long)arg1;

@end

