/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSObject.h"

@class DTXProxyChannel;

@interface _DTXProxy : NSObject
{
    DTXProxyChannel *_proxyChannel;
}

- (id)methodSignatureForSelector:(SEL)arg1;
- (void)forwardInvocation:(id)arg1;
- (void)dealloc;
- (id)initWithChannel:(id)arg1;

@end

