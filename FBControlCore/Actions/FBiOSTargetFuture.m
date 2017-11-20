/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBControlCore/FBiOSTargetFuture.h>

#import <objc/runtime.h>

#import "NSRunLoop+FBControlCore.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeApplicationLaunch = @"applaunch";

FBiOSTargetFutureType const FBiOSTargetFutureTypeAgentLaunch = @"agentlaunch";

FBiOSTargetFutureType const FBiOSTargetFutureTypeTestLaunch = @"launch_xctest";

@interface FBiOSTargetContinuation_Renamed : NSObject <FBiOSTargetContinuation>

@property (nonatomic, strong, readonly) id<FBiOSTargetContinuation> continuation;

@end

@implementation FBiOSTargetContinuation_Renamed

@synthesize handleType = _handleType;

- (instancetype)initWithAwaitable:(id<FBiOSTargetContinuation>)continuation handleType:(FBTerminationHandleType)handleType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _continuation = continuation;
  _handleType = handleType;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.continuation completed];
}

- (void)terminate
{
  return [self.continuation terminate];
}

- (FBTerminationHandleType)handleType
{
  return _handleType;
}

@end

@interface FBiOSTargetContinuation_Done : NSObject <FBiOSTargetContinuation>

@end

@implementation FBiOSTargetContinuation_Done

@synthesize handleType = _handleType;

- (instancetype)initWithHandleType:(FBTerminationHandleType)handleType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _handleType = handleType;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return [FBFuture futureWithResult:NSNull.null];
}

- (void)terminate
{
  // do nothing
}

- (FBTerminationHandleType)handleType
{
  return _handleType;
}

@end


id<FBiOSTargetContinuation> FBiOSTargetContinuationRenamed(id<FBiOSTargetContinuation> continuation, FBTerminationHandleType handleType)
{
  return [[FBiOSTargetContinuation_Renamed alloc] initWithAwaitable:continuation handleType:handleType];
}

id<FBiOSTargetContinuation> FBiOSTargetContinuationDone(FBTerminationHandleType handleType)
{
  return [[FBiOSTargetContinuation_Done alloc] initWithHandleType:handleType];
}

@implementation FBiOSTargetFutureSimple

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark JSON

- (nonnull id)jsonSerializableRepresentation
{
  return @{};
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  return [self new];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBiOSTargetFutureSimple *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }
  return YES;
}

- (NSUInteger)hash
{
  return NSStringFromClass(self.class).hash;
}

@end
