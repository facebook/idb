/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSObject.h>

#import <SimulatorApp/Indigo.h>

@interface SimDeviceLegacyClient : NSObject
{
    // Error parsing type: , name: _io
    // Error parsing type: , name: _performTargetRemapping
    // Error parsing type: , name: _ioPort
    // Error parsing type: , name: _descriptor
    // Error parsing type: , name: _hidCallbackUUID
    // Error parsing type: , name: _rwLock
    // Error parsing type: , name: _isWatch
    // Error parsing type: , name: _isTV
    // Error parsing type: , name: _isHIDArbitraryMessageAvailable
}

- (id)init;
- (void)sendWithMessage:(IndigoMessage *)arg1 freeWhenDone:(BOOL)arg2 completionQueue:(dispatch_queue_t)arg3 completion:(void (^)(NSError *))arg4;
- (void)sendWithMessage:(IndigoMessage *)arg1;
- (void)resetHIDSession;
- (void)dealloc;
- (id)initWithDevice:(id)arg1 error:(id *)arg2;

@end

