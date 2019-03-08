/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <DTXConnectionServices/DTXFileDescriptorTransport.h>

@interface DTXSocketTransport : DTXFileDescriptorTransport
{
    NSObject<OS_dispatch_semaphore> *_socketAcceptedSem;
    NSObject<OS_dispatch_source> *_acceptSource;
    NSArray *_addresses;
    int _port;
}

+ (id)addressForHost:(const char *)arg1 port:(int)arg2;
+ (id)schemes;
@property(readonly) int port; // @synthesize port=_port;
- (int)supportedDirections;
- (id)localAddresses;
- (void)disconnect;
- (unsigned long long)transmit:(const void *)arg1 ofLength:(unsigned long long)arg2;
- (id)initWithRemoteAddress:(id)arg1;
- (void)dealloc;
- (id)initWithLocalPort:(int)arg1;
- (id)initWithConnectedSocket:(int)arg1 disconnectAction:(CDUnknownBlockType)arg2;
- (void)_commonSocketTransportInit;
- (void)_setupChannelWithConnectedSocket:(int)arg1 assumingOwnership:(BOOL)arg2 orDisconnectBlock:(CDUnknownBlockType)arg3;
- (id)initWithLocalAddress:(id)arg1;
- (void)_setupWithLocalPort:(int)arg1;

@end

