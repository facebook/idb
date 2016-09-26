/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBInteraction.h"

#import "FBControlCoreError.h"

@interface FBInteraction_Block : NSObject <FBInteraction>

@property (nonatomic, copy, readonly) BOOL (^block)(NSError **error);

@end

@implementation FBInteraction_Block

- (instancetype)initWithBlock:( BOOL(^)(NSError **error) )block
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _block = block;

  return self;
}

- (BOOL)perform:(NSError **)error
{
  NSError *innerError = nil;
  BOOL success = self.block(&innerError);
  if (!success && error) {
    *error = innerError;
  }
  return success;
}

@end

@interface FBInteraction_Sequence : NSObject <FBInteraction>

@property (nonatomic, copy, readonly) NSArray<id<FBInteraction>> *interactions;

@end

@implementation FBInteraction_Sequence

- (instancetype)initWithInteractions:(NSArray<id<FBInteraction>> *)interactions
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _interactions = interactions;

  return self;
}

- (BOOL)perform:(NSError **)error
{
  for (id<FBInteraction> interaction in self.interactions) {
    NSError *innerError = nil;
    if (![interaction perform:&innerError]) {
      return [FBControlCoreError failBoolWithError:innerError errorOut:error];
    }
  }
  return YES;
}

@end

@interface FBInteraction_Success : NSObject <FBInteraction>

@end

@implementation FBInteraction_Success

- (BOOL)perform:(NSError **)error
{
  return YES;
}

@end

@interface FBInteraction_Failure : NSObject <FBInteraction>

@property (atomic, strong, nonnull, readonly) NSError *error;

@end

@implementation FBInteraction_Failure

- (instancetype)initWithError:(NSError *)error
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _error = error;

  return self;
}

- (BOOL)perform:(NSError **)errorPtr
{
  if (errorPtr) {
    *errorPtr = self.error;
  }
  return NO;
}

@end

@interface FBInteraction_Retrying : NSObject <FBInteraction>

@property (nonatomic, strong, readonly) id<FBInteraction> interaction;
@property (nonatomic, assign, readonly) NSUInteger retries;

@end

@implementation FBInteraction_Retrying

- (instancetype)initWithInteraction:(id<FBInteraction>)interaction retries:(NSUInteger)retries
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _interaction = interaction;
  _retries = retries;

  return self;
}

- (BOOL)perform:(NSError **)error
{
  NSError *innerError = nil;
  for (NSUInteger index = 0; index < self.retries; index++) {
    if ([self.interaction perform:&innerError]) {
      return YES;
    }
  }
  return [[[FBControlCoreError
    describeFormat:@"Failed interaction after %ld retries", self.retries]
    causedBy:innerError]
    failBool:error];
}

@end

@implementation FBInteraction

#pragma mark Initializers

- (instancetype)init
{
  return [self initWithInteraction:FBInteraction.succeed];
}

- (instancetype)initWithInteraction:(id<FBInteraction>)interaction
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _interaction = interaction ?: FBInteraction.succeed;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc] initWithInteraction:self.interaction];
}

#pragma mark Primitives

+ (id<FBInteraction>)interact:(BOOL (^)(NSError **error))block
{
  NSParameterAssert(block);
  return [[FBInteraction_Block alloc] initWithBlock:block];
}

+ (id<FBInteraction>)fail:(NSError *)error
{
  NSParameterAssert(error);
  return [[FBInteraction_Failure alloc] initWithError:error];
}

+ (id<FBInteraction>)succeed
{
  return [FBInteraction_Success new];
}

+ (id<FBInteraction>)retry:(NSUInteger)retries interaction:(id<FBInteraction>)interaction;
{
  NSParameterAssert(retries > 1);
  NSParameterAssert(interaction);
  return [[FBInteraction_Retrying alloc] initWithInteraction:interaction retries:retries];
}

+ (id<FBInteraction>)ignoreFailure:(id<FBInteraction>)interaction
{
  NSParameterAssert(interaction);

  return [self interact:^ BOOL (NSError **error) {
    NSError *innerError = nil;
    [interaction perform:&innerError];
    return YES;
  }];
}

+ (id<FBInteraction>)sequence:(NSArray<id<FBInteraction>> *)interactions
{
  return [[FBInteraction_Sequence alloc] initWithInteractions:interactions];
}

+ (id<FBInteraction>)first:(id<FBInteraction>)first second:(id<FBInteraction>)second
{
  NSParameterAssert(first);
  NSParameterAssert(second);
  return [self sequence:@[first, second]];
}

#pragma mark Chainable Interactions

- (instancetype)chainNext:(id<FBInteraction>)next
{
  NSParameterAssert(next);
  FBInteraction *interaction = [self copy];
  interaction->_interaction = [FBInteraction first:self.interaction second:next];
  return interaction;
}

- (instancetype)interact:(BOOL (^)(NSError **error, id interaction))block
{
  __weak id weakInteraction = self;
  id<FBInteraction> next = [FBInteraction interact:^ BOOL (NSError **error) {
    __strong id strongInteraction = weakInteraction;
    return block(error, strongInteraction);
  }];

  return [self chainNext:next];
}

- (instancetype)succeed
{
  return self;
}

- (instancetype)fail:(NSError *)error
{
  return [self chainNext:[FBInteraction fail:error]];
}

#pragma mark FBInteraction

- (BOOL)perform:(NSError **)error
{
  return [self.interaction perform:error];
}

@end
