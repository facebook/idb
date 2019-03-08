/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSObject.h"

#import "DTXAllowedRPC.h"

@class DTXChannel, NSString;

@interface DTXService : NSObject <DTXAllowedRPC>
{
    DTXChannel *_channel;
}

+ (void)registerCapabilities:(id)arg1;
+ (BOOL)automaticallyRegistersCapabilities;
+ (void)instantiateServiceWithChannel:(id)arg1;
@property(readonly, retain, nonatomic) DTXChannel *channel; // @synthesize channel=_channel;
- (void)messageReceived:(id)arg1;
- (void)dealloc;
- (id)initWithChannel:(id)arg1;

// Remaining properties
@property(readonly, copy) NSString *debugDescription;
@property(readonly, copy) NSString *description;
@property(readonly) unsigned long long hash;
@property(readonly) Class superclass;

@end

