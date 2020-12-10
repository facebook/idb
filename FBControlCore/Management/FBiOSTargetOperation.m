/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetOperation.h"

#import <objc/runtime.h>

#import "FBFuture+Sync.h"

FBiOSTargetOperationType const FBiOSTargetOperationTypeApplicationLaunch = @"applaunch";

FBiOSTargetOperationType const FBiOSTargetOperationTypeAgentLaunch = @"agentlaunch";

FBiOSTargetOperationType const FBiOSTargetOperationTypeTestLaunch = @"launch_xctest";

FBiOSTargetOperationType const FBiOSTargetOperationTypeLogTail = @"logtail";

@interface FBiOSTargetOperation_Named : NSObject <FBiOSTargetOperation>

@end

@implementation FBiOSTargetOperation_Named

@synthesize completed = _completed;
@synthesize operationType = _operationType;

- (instancetype)initWithCompleted:(FBFuture<NSNull *> *)completed operationType:(FBiOSTargetOperationType)operationType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _completed = completed;
  _operationType = operationType;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return _completed;
}

- (FBiOSTargetOperationType)operationType
{
  return _operationType;
}

@end

@interface FBiOSTargetOperation_Renamed : NSObject <FBiOSTargetOperation>

@property (nonatomic, strong, readonly) id<FBiOSTargetOperation> operation;

@end

@implementation FBiOSTargetOperation_Renamed

@synthesize operationType = _operationType;

- (instancetype)initWithAwaitable:(id<FBiOSTargetOperation>)operation operationType:(FBiOSTargetOperationType)operationType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _operation = operation;
  _operationType = operationType;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.operation completed];
}

- (FBiOSTargetOperationType)operationType
{
  return _operationType;
}

@end

@interface FBiOSTargetOperation_Done : NSObject <FBiOSTargetOperation>

@end

@implementation FBiOSTargetOperation_Done

@synthesize operationType = _operationType;

- (instancetype)initWithOperationType:(FBiOSTargetOperationType)operationType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _operationType = operationType;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return FBFuture.empty;
}

- (FBiOSTargetOperationType)operationType
{
  return _operationType;
}

@end

id<FBiOSTargetOperation> FBiOSTargetOperationNamed(FBFuture<NSNull *> *completed, FBiOSTargetOperationType operationType)
{
  return [[FBiOSTargetOperation_Named alloc] initWithCompleted:completed operationType:operationType];
}

id<FBiOSTargetOperation> FBiOSTargetOperationRenamed(id<FBiOSTargetOperation> operation, FBiOSTargetOperationType operationType)
{
  return [[FBiOSTargetOperation_Renamed alloc] initWithAwaitable:operation operationType:operationType];
}

id<FBiOSTargetOperation> FBiOSTargetOperationDone(FBiOSTargetOperationType operationType)
{
  return [[FBiOSTargetOperation_Done alloc] initWithOperationType:operationType];
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
