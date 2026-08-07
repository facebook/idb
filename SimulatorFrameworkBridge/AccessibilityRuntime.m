/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityRuntime.h"

#import "AXRuntimePrivate.h"

@implementation FBAXReadOutcome

- (instancetype)initWithStatus:(FBAXReadStatus)status
                    attributes:(nullable NSDictionary<NSString *, id> *)attributes
                         error:(nullable NSError *)error
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _status = status;
  _attributes = [attributes copy];
  _error = error;
  return self;
}

+ (instancetype)read:(NSDictionary<NSString *, id> *)attributes
{
  return [[self alloc] initWithStatus:FBAXReadStatusRead attributes:attributes error:nil];
}

+ (instancetype)applicationUnavailable
{
  return [[self alloc] initWithStatus:FBAXReadStatusApplicationUnavailable attributes:nil error:nil];
}

+ (instancetype)failed:(nullable NSError *)error
{
  return [[self alloc] initWithStatus:FBAXReadStatusFailed attributes:nil error:error];
}

+ (instancetype)failureForAttributeError:(nullable NSError *)error
{
  // FBAXErrorServerNotFound means nothing answered, rather than that the answer was bad — the one failure
  // the host maps onto a typed, backend-neutral error, so it is recognised by the code the runtime
  // reports rather than by matching on a message.
  NSNumber *code = error.userInfo[FBAXAccessibilityErrorKey];
  if ([code isKindOfClass:NSNumber.class] && code.intValue == FBAXErrorServerNotFound) {
    return [self applicationUnavailable];
  }
  return [self failed:error];
}

@end

@implementation FBAXHitTestOutcome

- (instancetype)initWithStatus:(FBAXHitTestStatus)status
                       element:(nullable XCAccessibilityElement *)element
       owningProcessIdentifier:(pid_t)pid
                 failureReason:(nullable NSString *)failureReason
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _status = status;
  _element = element;
  _owningProcessIdentifier = pid;
  _failureReason = [failureReason copy];
  return self;
}

+ (instancetype)hit:(XCAccessibilityElement *)element owningProcessIdentifier:(pid_t)pid
{
  return [[self alloc] initWithStatus:FBAXHitTestStatusHit
                              element:element
              owningProcessIdentifier:pid
                        failureReason:nil];
}

+ (instancetype)empty
{
  return [[self alloc] initWithStatus:FBAXHitTestStatusEmpty
                              element:nil
              owningProcessIdentifier:0
                        failureReason:nil];
}

+ (instancetype)applicationUnavailable
{
  return [[self alloc] initWithStatus:FBAXHitTestStatusApplicationUnavailable
                              element:nil
              owningProcessIdentifier:0
                        failureReason:nil];
}

+ (instancetype)failed:(NSString *)failureReason
{
  return [[self alloc] initWithStatus:FBAXHitTestStatusFailed
                              element:nil
              owningProcessIdentifier:0
                        failureReason:failureReason];
}

@end
