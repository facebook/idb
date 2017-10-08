/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

