/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBLogTailConfiguration.h"

FBiOSTargetActionType const FBiOSTargetActionTypeLogTail = @"logtail";

@implementation FBLogTailConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithArguments:(NSArray<NSString *> *)arguments
{
  return [[self alloc] initWithArguments:arguments];
}

- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _arguments = arguments;
  return self;
}

#pragma mark JSON

static NSString *const KeyArguments = @"arguments";

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ should be a Dictionary<string, object>", json]
      fail:error];
  }
  NSArray<NSString *> *arguments = json[KeyArguments] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:arguments withClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not an Array<String> for %@", arguments, KeyArguments]
      fail:error];
  }
  return [self configurationWithArguments:arguments];
}

- (id)jsonSerializableRepresentation
{
  return @{
   KeyArguments: self.arguments,
 };
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Log Tail Args %@",
    [FBCollectionInformation oneLineDescriptionFromArray:self.arguments]
  ];
}

- (BOOL)isEqual:(FBLogTailConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }
  return [self.arguments isEqualToArray:configuration.arguments];
}

- (NSUInteger)hash
{
  return self.arguments.hash ^ [NSStringFromClass(self.class) hash];
}

#pragma mark FBiOSTargetFuture

- (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeLogTail;
}

- (FBFuture<FBiOSTargetActionType> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter awaitableDelegate:(id<FBiOSTargetActionAwaitableDelegate>)awaitableDelegate
{
  id<FBLogCommands> commands = (id<FBLogCommands>) target;
  if (![target conformsToProtocol:@protocol(FBLogCommands)]) {
    return [[FBControlCoreError
      describeFormat:@"%@ does not support FBLogCommands", target]
      failFuture];
  }
  FBiOSTargetActionType actionType = self.actionType;
  return [[commands
    tailLog:self.arguments consumer:consumer]
    onQueue:target.workQueue map:^(id<FBTerminationAwaitable> baseAwaitable) {
      id<FBTerminationAwaitable> awaitable = FBTerminationAwaitableRenamed(baseAwaitable, actionType);
      [awaitableDelegate action:(id<FBiOSTargetAction>)self target:target didGenerateAwaitable:awaitable];
      return self.actionType;
    }];
}

@end
