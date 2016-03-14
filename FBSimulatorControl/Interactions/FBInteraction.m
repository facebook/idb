/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBInteraction.h"

#import "FBSimulatorError.h"

@interface FBInteraction ()

#pragma mark Primitives

/**
 Chains an interaction using the provided block

 @param block the block to perform the interaction with. Passes an NSError to return error information and the interaction for further chaining.
 @return the reciever, for chaining.
 */
+ (id<FBInteraction>)interact:(BOOL (^)(NSError **error))block;

/**
 Creates an Interaction that allways Fails.

 @param error the error to fail the interaction with.
 @return an Interaction that allways Fails.
 */
+ (id<FBInteraction>)fail:(NSError *)error;

/**
 Creates an Interaction that always Succeeds.

 @return an Interaction that always Succeeds.
 */
+ (id<FBInteraction>)succeed;

/**
 Creates an Interaction that will retry a base interaction a number of times, before failing.

 @param retries the number of retries, must be 1 or greater.
 @param interaction the base interaction to retry.
 @return a retrying interaction.
 */
+ (id<FBInteraction>)retry:(NSUInteger)retries interaction:(id<FBInteraction>)interaction;

/**
 Ignores any failure that occurs to the base interaction.

 @param interaction the interaction to attempt.
 @return an interaction that allways succeds.
 */
+ (id<FBInteraction>)ignoreFailure:(id<FBInteraction>)interaction;

/**
 Takes an NSArray<id<FBInteraction>> and returns an id<FBInteracton>.
 Any failing interaction will terminate the chain.

 @param interactions the interactions to chain together.
 */
+ (id<FBInteraction>)sequence:(NSArray *)interactions;

/**
 Joins to interactions together.
 Equivalent to [FBInteraction sequence:@[first, second]]

 @param first the interaction to perform first.
 @param second the interaction to perform second.
 @return a chained interaction.
 */
+ (id<FBInteraction>)first:(id<FBInteraction>)first second:(id<FBInteraction>)second;

@end

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

@property (nonatomic, copy, readonly) NSArray *interactions;

@end

@implementation FBInteraction_Sequence

- (instancetype)initWithInteractions:(NSArray *)interactions
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
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
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
  return [[[FBSimulatorError
    describeFormat:@"Failed interaction after %ld retries", self.retries]
    causedBy:innerError]
    failBool:error];
}

@end

@implementation FBInteraction

#pragma mark Initializers

- (instancetype)init
{
  return [self initWithInteraction:nil];
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

+ (id<FBInteraction>)sequence:(NSArray *)interactions
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

#pragma mark Private

- (instancetype)chainNext:(id<FBInteraction>)next
{
  FBInteraction *interaction = [self copy];
  interaction->_interaction = [FBInteraction first:self.interaction second:next];
  return interaction;
}

@end
