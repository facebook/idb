/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestManagerLoggingForwarder.h"

#import <XCTest/XCTestManager_IDEInterface-Protocol.h>

#import <FBControlCore/FBControlCore.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBXCTestManagerLoggingForwarder() <XCTestManager_IDEInterface>

@end

@implementation FBXCTestManagerLoggingForwarder

+ (instancetype)withIDEInterface:(id<XCTestManager_IDEInterface, NSObject>)interface logger:(id<FBControlCoreLogger>)logger
{
  return [[FBXCTestManagerLoggingForwarder alloc] initWithIDEInterface:interface logger:logger];
}

- (instancetype)initWithIDEInterface:(id<XCTestManager_IDEInterface, NSObject>)interface logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _interface = interface;
  _logger = logger;

  return self;
}

#pragma mark Delegate Forwarding

- (BOOL)respondsToSelector:(SEL)selector
{
  return [super respondsToSelector:selector] || [self.interface respondsToSelector:selector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
  return [super methodSignatureForSelector:selector] ?: [(id)self.interface methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
  if ([self.interface respondsToSelector:invocation.selector]) {
    [self.logger log:NSStringFromSelector(invocation.selector)];
    [invocation invokeWithTarget:self.interface];
  } else {
    [super forwardInvocation:invocation];
  }
}

#pragma mark Blackholing Some Logging

- (id)_XCT_logDebugMessage:(NSString *)arg1
{
  return [self.interface _XCT_logDebugMessage:arg1];
}

@end

#pragma clang diagnostic pop
