/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <DTXConnectionServices/DTXTransport.h>

#import "NSURLSessionDelegate.h"

@class NSString, NSURLSession, NSURLSessionDataTask;

@interface DTXFoundationURLTransport : DTXTransport <NSURLSessionDelegate>
{
    NSURLSession *_session;
    NSURLSessionDataTask *_dataTask;
}

+ (id)schemes;
- (void)disconnect;
- (void)URLSession:(id)arg1 task:(id)arg2 didCompleteWithError:(id)arg3;
- (unsigned long long)transmit:(const void *)arg1 ofLength:(unsigned long long)arg2;
- (void)URLSession:(id)arg1 dataTask:(id)arg2 didReceiveData:(id)arg3;
- (void)_shutDownSession;
- (id)initWithRemoteAddress:(id)arg1;
- (int)supportedDirections;
- (id)initWithLocalAddress:(id)arg1;

// Remaining properties
@property(readonly, copy) NSString *debugDescription;
@property(readonly, copy) NSString *description;
@property(readonly) unsigned long long hash;
@property(readonly) Class superclass;

@end

