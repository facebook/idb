/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilitySnapshotClient.h"

#import "AccessibilityRuntime.h"
#import "Private/AccessibilityElement_Private.h"

static NSString *const kSnapshotAttributes = @"UIAccessibilitySnapshotKeyAttributes";
static NSString *const kSnapshotChildren = @"UIAccessibilitySnapshotKeyChildren";
static NSString *const kSnapshotElement = @"UIAccessibilitySnapshotKeyElement";
static NSString *const kChildrenAttribute = @"XC_kAXXCAttributeChildren";

static void FBAXSnapshotException(NSException *exception, NSError **error)
{
  NSLog(@"[AccessibilityService] answering a request raised: %@", exception);
  if (error) {
    *error = [NSError errorWithDomain:@"FBAXRuntimeException" code:1 userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: exception.name}];
  }
}

@interface FBAXSnapshotAttribute ()

- (instancetype)initWithName:(NSString *)name value:(id)value;

@end

@implementation FBAXSnapshotAttribute

- (instancetype)initWithName:(NSString *)name value:(id)value
{
  self = [super init];
  if (self) {
    _name = [name copy];
    _value = value;
  }
  return self;
}

@end

@interface FBAXSnapshotNode ()

@property (nonatomic, readonly) id value;
@property (nonatomic, readonly, getter = isValid) BOOL valid;
@property (nonatomic, readonly) id owner;
@property (nullable, nonatomic, readonly, copy) NSDictionary<NSNumber *, NSString *> *namesByNumber;
@property (nullable, nonatomic, readonly) id element;

- (instancetype)initWithValue:(id)value owner:(id)owner namesByNumber:(nullable NSDictionary<NSNumber *, NSString *> *)namesByNumber;

@end

@implementation FBAXSnapshotNode

- (instancetype)initWithValue:(id)value owner:(id)owner namesByNumber:(NSDictionary<NSNumber *, NSString *> *)namesByNumber
{
  self = [super init];
  if (self) {
    _value = value;
    _owner = owner;
    _namesByNumber = [namesByNumber copy];
  }
  return self;
}

- (BOOL)isValid
{
  return [self.value isKindOfClass:NSDictionary.class];
}

- (id)element
{
  return self.isValid ? ((NSDictionary *)self.value)[kSnapshotElement] : nil;
}

- (NSNumber *)validWithError:(NSError **)error
{
  @try {
    return @(self.isValid);
  } @catch (NSException *exception) {
    FBAXSnapshotException(exception, error);
    return nil;
  }
}

- (NSArray<FBAXSnapshotAttribute *> *)attributesWithError:(NSError **)error
{
  @try {
    NSDictionary *attributes = self.isValid ? ((NSDictionary *)self.value)[kSnapshotAttributes] : nil;
    NSMutableArray<FBAXSnapshotAttribute *> *named = [NSMutableArray array];
    if ([attributes isKindOfClass:NSDictionary.class]) {
      for (NSNumber *number in attributes) {
        NSString *name = self.namesByNumber[number];
        if (name && ![name isEqualToString:kChildrenAttribute]) {
          [named addObject:[[FBAXSnapshotAttribute alloc] initWithName:name value:attributes[number]]];
        }
      }
    }
    return named;
  } @catch (NSException *exception) {
    FBAXSnapshotException(exception, error);
    return nil;
  }
}

- (NSArray<FBAXSnapshotNode *> *)childrenWithError:(NSError **)error
{
  @try {
    id nesting = self.isValid ? ((NSDictionary *)self.value)[kSnapshotChildren] : nil;
    if (![nesting isKindOfClass:NSArray.class]) {
      return @[];
    }
    NSMutableArray<FBAXSnapshotNode *> *children = [NSMutableArray array];
    for (id value in nesting) {
      [children addObject:[[FBAXSnapshotNode alloc] initWithValue:value owner:self.owner namesByNumber:self.namesByNumber]];
    }
    return children;
  } @catch (NSException *exception) {
    FBAXSnapshotException(exception, error);
    return nil;
  }
}

@end

@interface FBAXSnapshotRead ()

- (instancetype)initWithSnapshot:(nullable id)snapshot namesByNumber:(nullable NSDictionary<NSNumber *, NSString *> *)namesByNumber error:(nullable NSError *)error;

@end

@implementation FBAXSnapshotRead

- (instancetype)initWithSnapshot:(id)snapshot namesByNumber:(NSDictionary<NSNumber *, NSString *> *)namesByNumber error:(NSError *)error
{
  self = [super init];
  if (self) {
    _root = snapshot ? [[FBAXSnapshotNode alloc] initWithValue:snapshot owner:snapshot namesByNumber:namesByNumber] : nil;
    _error = error;
  }
  return self;
}

@end

@implementation FBAXSnapshotClient
{
  id<FBAXRuntime> _runtime;
}

- (instancetype)initWithRuntime:(id<FBAXRuntime>)runtime
{
  self = [super init];
  if (self) {
    _runtime = runtime;
  }
  return self;
}

- (FBAXSnapshotRead *)readElement:(FBAXElement *)element attributeNames:(NSArray<NSString *> *)names error:(NSError **)error
{
  @try {
    NSDictionary<NSNumber *, NSString *> *namesByNumber = nil;
    NSError *readError = nil;
    id snapshot = [_runtime snapshotOfElement:element.value attributeNames:names namesByNumber:&namesByNumber error:&readError];
    return [[FBAXSnapshotRead alloc] initWithSnapshot:snapshot namesByNumber:namesByNumber error:readError];
  } @catch (NSException *exception) {
    FBAXSnapshotException(exception, error);
    return nil;
  }
}

- (FBAXSnapshotRead *)readContinuation:(FBAXSnapshotNode *)node attributeNames:(NSArray<NSString *> *)names error:(NSError **)error
{
  @try {
    // The raw element can borrow storage from the snapshot dictionary.
    NS_VALID_UNTIL_END_OF_SCOPE FBAXSnapshotNode *owner = node;
    NSDictionary<NSNumber *, NSString *> *namesByNumber = nil;
    NSError *readError = nil;
    id snapshot = [_runtime snapshotOfSnapshotElement:owner.element attributeNames:names namesByNumber:&namesByNumber error:&readError];
    return [[FBAXSnapshotRead alloc] initWithSnapshot:snapshot namesByNumber:namesByNumber error:readError];
  } @catch (NSException *exception) {
    FBAXSnapshotException(exception, error);
    return nil;
  }
}

- (NSNumber *)processIdentifierForNode:(FBAXSnapshotNode *)node error:(NSError **)error
{
  @try {
    NS_VALID_UNTIL_END_OF_SCOPE FBAXSnapshotNode *owner = node;
    id element = owner.element;
    return @(element ? [_runtime owningProcessIdentifierForSnapshotElement:element] : 0);
  } @catch (NSException *exception) {
    FBAXSnapshotException(exception, error);
    return nil;
  }
}

@end
