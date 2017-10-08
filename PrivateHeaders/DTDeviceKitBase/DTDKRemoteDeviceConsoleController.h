/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class DTDKRemoteDeviceToken, DVTDispatchLock, NSString;
@protocol DTDKRemoteDeviceConsoleControllerDelegate;

@interface DTDKRemoteDeviceConsoleController : NSObject
{
    struct _AMDServiceConnection *_serviceRef;
    NSObject<OS_dispatch_queue> *_queue;
    NSObject<OS_dispatch_queue> *_socketQueue;
    NSObject<OS_dispatch_source> *_consoleSource;
    _Bool _isInvalidating;
    struct DTDKCircularBuffer *_circularBuffer;
    DVTDispatchLock *_bufferLock;
    id <DTDKRemoteDeviceConsoleControllerDelegate> _delegate;
    DTDKRemoteDeviceToken *_token;
}
@property __weak DTDKRemoteDeviceToken *token; // @synthesize token=_token;
@property(retain) id <DTDKRemoteDeviceConsoleControllerDelegate> delegate; // @synthesize delegate=_delegate;
@property(readonly, copy) NSString *consoleString;

+ (id)consoleStringWithData:(id)arg1 startingAtOffset:(unsigned long long)arg2;
+ (id)controllerForDevice:(id)arg1;
- (void)clear;
- (void)reload;
- (void)invalidate;
- (void)dealloc;

@end

