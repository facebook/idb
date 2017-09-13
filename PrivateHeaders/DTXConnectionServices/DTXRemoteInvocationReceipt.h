/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <DTXConnectionServices/CDStructures.h>

@interface DTXRemoteInvocationReceipt : NSObject
{
    NSObject<OS_dispatch_queue> *_guard;
    CDUnknownBlockType _completionHandler;
    id _returnValue;
    unsigned int _returnType;
}

- (void)invokeCompletionWithReturnValue:(id)arg1 error:(id)arg2;
- (void)handleCompletion:(void(^)(NSNumber *version, NSError *error))arg1;
- (void)_checkedAssign:(CDUnknownBlockType)arg1;
- (void)dealloc;
- (id)init;

@end
