/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetOperation.h"

#import <objc/runtime.h>

#import "FBFuture+Sync.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeApplicationLaunch = @"applaunch";

FBiOSTargetFutureType const FBiOSTargetFutureTypeAgentLaunch = @"agentlaunch";

FBiOSTargetFutureType const FBiOSTargetFutureTypeTestLaunch = @"launch_xctest";

FBiOSTargetFutureType const FBiOSTargetFutureTypeLogTail = @"logtail";

@interface FBiOSTargetOperation_Named : NSObject <FBiOSTargetOperation>

@end

@implementation FBiOSTargetOperation_Named

@synthesize completed = _completed;
@synthesize futureType = _futureType;

- (instancetype)initWithCompleted:(FBFuture<NSNull *> *)completed futureType:(FBiOSTargetFutureType)futureType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _completed = completed;
  _futureType = futureType;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return _completed;
}

- (FBiOSTargetFutureType)futureType
{
  return _futureType;
}

@end

@interface FBiOSTargetOperation_Renamed : NSObject <FBiOSTargetOperation>

@property (nonatomic, strong, readonly) id<FBiOSTargetOperation> operation;

@end

@implementation FBiOSTargetOperation_Renamed

@synthesize futureType = _futureType;

- (instancetype)initWithAwaitable:(id<FBiOSTargetOperation>)operation futureType:(FBiOSTargetFutureType)futureType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _operation = operation;
  _futureType = futureType;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.operation completed];
}

- (FBiOSTargetFutureType)futureType
{
  return _futureType;
}

@end

@interface FBiOSTargetOperation_Done : NSObject <FBiOSTargetOperation>

@end

@implementation FBiOSTargetOperation_Done

@synthesize futureType = _futureType;

- (instancetype)initWithFutureType:(FBiOSTargetFutureType)futureType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _futureType = futureType;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return FBFuture.empty;
}

- (FBiOSTargetFutureType)futureType
{
  return _futureType;
}

@end

id<FBiOSTargetOperation> FBiOSTargetOperationNamed(FBFuture<NSNull *> *completed, FBiOSTargetFutureType futureType)
{
  return [[FBiOSTargetOperation_Named alloc] initWithCompleted:completed futureType:futureType];
}

id<FBiOSTargetOperation> FBiOSTargetOperationRenamed(id<FBiOSTargetOperation> operation, FBiOSTargetFutureType futureType)
{
  return [[FBiOSTargetOperation_Renamed alloc] initWithAwaitable:operation futureType:futureType];
}

id<FBiOSTargetOperation> FBiOSTargetOperationDone(FBiOSTargetFutureType futureType)
{
  return [[FBiOSTargetOperation_Done alloc] initWithFutureType:futureType];
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
