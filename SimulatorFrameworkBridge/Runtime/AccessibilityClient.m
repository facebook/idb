/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityClient.h"

#import "AXPAttributes.h"
#import "Private/AccessibilityElement_Private.h"

static void FBAXClientException(NSException *exception, NSError **error)
{
  NSLog(@"[AccessibilityService] answering a request raised: %@", exception);
  if (error) {
    *error = [NSError errorWithDomain:@"FBAXRuntimeException" code:1 userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: exception.name}];
  }
}

@implementation FBAXElement
- (instancetype)initWithValue:(id)value
{
  self = [super init];
  if (self) {
    _value = value;
  }
  return self;
}

@end

@interface FBAXOptionalValue ()
- (instancetype)initWithValue:(nullable id)value;
@end

@implementation FBAXOptionalValue
- (instancetype)initWithValue:(id)value
{
  self = [super init];
  if (self) {
    _value = value;
  }
  return self;
}

@end

@interface FBAXElementHit ()
- (instancetype)initWithOutcome:(FBAXHitTestOutcome *)outcome;
@end

@implementation FBAXElementHit
- (instancetype)initWithOutcome:(FBAXHitTestOutcome *)outcome
{
  self = [super init];
  if (self) {
    _status = outcome.status;
    _element = outcome.element ? [[FBAXElement alloc] initWithValue:outcome.element] : nil;
    _owningProcessIdentifier = outcome.owningProcessIdentifier;
    _failureReason = [outcome.failureReason copy];
  }
  return self;
}

@end

@interface FBAXElementRead ()
- (instancetype)initWithOutcome:(FBAXReadOutcome *)outcome;
@end

@implementation FBAXElementRead
- (instancetype)initWithOutcome:(FBAXReadOutcome *)outcome
{
  self = [super init];
  if (self) {
    _status = outcome.status;
    _attributes = [outcome.attributes copy];
    _error = outcome.error;
  }
  return self;
}

- (NSArray<FBAXElement *> *)childrenWithError:(NSError **)error
{
  @try {
    id values = self.attributes[@"XC_kAXXCAttributeChildren"];
    if (![values isKindOfClass:NSArray.class]) {
      return @[];
    }
    NSMutableArray<FBAXElement *> *children = [NSMutableArray array];
    for (id value in values) {
      [children addObject:[[FBAXElement alloc] initWithValue:value]];
    }
    return children;
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

@end

@interface FBAXTranslatorRead ()
- (instancetype)initWithValues:(nullable NSDictionary<NSNumber *, id> *)values;
@end

@implementation FBAXTranslatorRead
- (instancetype)initWithValues:(NSDictionary<NSNumber *, id> *)values
{
  self = [super init];
  if (self) {
    _available = values != nil;
    _label = values[@(FBAXPAttributeLabel)];
    _frame = values[@(FBAXPAttributeFrame)];
    _identifier = values[@(FBAXPAttributeIdentifier)];
    _value = values[@(FBAXPAttributeValue)];
    _visible = values[@(FBAXPAttributeIsVisible)];
    _enabled = values[@(FBAXPAttributeIsEnabled)];
    _role = values[@(FBAXPAttributeRole)];
    _subrole = values[@(FBAXPAttributeSubrole)];
    _visiblePoint = values[@(FBAXPAttributeVisiblePoint)];
    _traits = values[@(FBAXPAttributeTraits)];
    _memoryAddress = values[@(FBAXPAttributeMemoryAddress)];
  }
  return self;
}

@end

@implementation FBAXClient
{
  id<FBAXRuntime> _runtime;
}

- (instancetype)initWithRuntime:(id<FBAXRuntime>)runtime
{
  self = [super init];
  if (self) {
    _runtime = runtime;
    _snapshots = [[FBAXSnapshotClient alloc] initWithRuntime:runtime];
  }
  return self;
}

- (FBAXOptionalValue<FBAXElement *> *)applicationElementForProcessIdentifier:(pid_t)pid error:(NSError **)error
{
  @try {
    id value = [_runtime applicationElementForProcessIdentifier:pid];
    FBAXElement *element = value ? [[FBAXElement alloc] initWithValue:value] : nil;
    return [[FBAXOptionalValue alloc] initWithValue:element];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXElementRead *)readAttributes:(NSArray<NSString *> *)attributes ofElement:(FBAXElement *)element error:(NSError **)error
{
  @try {
    return [[FBAXElementRead alloc] initWithOutcome:[_runtime readAttributes:attributes ofElement:element.value]];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXElementHit *)hitTestAtPoint:(CGPoint)point processIdentifier:(pid_t)pid error:(NSError **)error
{
  @try {
    return [[FBAXElementHit alloc] initWithOutcome:[_runtime hitTestAtPoint:point processIdentifier:pid]];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXWriteOutcome *)performAction:(FBAXAction)action onElement:(FBAXElement *)element error:(NSError **)error
{
  @try {
    return [_runtime performAction:action onElement:element.value];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXWriteOutcome *)setValue:(id)value onElement:(FBAXElement *)element error:(NSError **)error
{
  @try {
    return [_runtime setValue:value onElement:element.value];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXFrontmostOutcome *)windowServerFrontmostWithError:(NSError **)error
{
  @try {
    return [_runtime windowServerFrontmost];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXFrontmostOutcome *)runningBoardFrontmostWithError:(NSError **)error
{
  @try {
    return [_runtime runningBoardFrontmost];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (NSNumber *)automationModeEnabledWithError:(NSError **)error
{
  @try {
    return @([_runtime automationModeEnabled]);
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (NSNumber *)setAutomationModeEnabled:(BOOL)enabled error:(NSError **)error
{
  @try {
    return @([_runtime setAutomationModeEnabled:enabled]);
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXDeviceSettingOutcome *)enabledStateForDeviceSetting:(FBAXDeviceSetting)setting error:(NSError **)error
{
  @try {
    return [_runtime enabledStateForDeviceSetting:setting];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXDeviceSettingOutcome *)setEnabled:(BOOL)enabled forDeviceSetting:(FBAXDeviceSetting)setting error:(NSError **)error
{
  @try {
    return [_runtime setEnabled:enabled forDeviceSetting:setting];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXTranslatorRead *)translatorAttributesOfElement:(FBAXElement *)element error:(NSError **)error
{
  @try {
    NSArray<NSNumber *> *attributes = @[
      @(FBAXPAttributeLabel), @(FBAXPAttributeFrame), @(FBAXPAttributeIdentifier),
      @(FBAXPAttributeValue), @(FBAXPAttributeIsVisible), @(FBAXPAttributeIsEnabled),
      @(FBAXPAttributeRole), @(FBAXPAttributeSubrole), @(FBAXPAttributeVisiblePoint),
      @(FBAXPAttributeTraits), @(FBAXPAttributeMemoryAddress),
    ];
    return [[FBAXTranslatorRead alloc] initWithValues:[_runtime translatorAttributes:attributes ofElement:element.value]];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (NSArray<FBAXElement *> *)translatorChildrenOfElement:(FBAXElement *)element error:(NSError **)error
{
  @try {
    NSDictionary<NSNumber *, id> *values = [_runtime translatorAttributes:@[@(FBAXPAttributeChildren)] ofElement:element.value];
    id list = values[@(FBAXPAttributeChildren)];
    if (![list isKindOfClass:NSArray.class]) {
      return @[];
    }
    NSMutableArray<FBAXElement *> *children = [NSMutableArray array];
    for (id value in list) {
      [children addObject:[[FBAXElement alloc] initWithValue:value]];
    }
    return children;
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXOptionalValue<NSValue *> *)rectangleFromValue:(id)value error:(NSError **)error
{
  @try {
    CGRect geometry = CGRectZero;
    BOOL valid = NO;
    if ([value isKindOfClass:NSValue.class]) {
      if (strcmp([value objCType], @encode(CGRect)) == 0) {
        [value getValue:&geometry size:sizeof(geometry)];
        valid = YES;
      }
    } else {
      valid = [_runtime getRect:&geometry fromValue:value];
    }
    return [[FBAXOptionalValue alloc] initWithValue:valid ? [NSValue valueWithBytes:&geometry objCType:@encode(CGRect)] : nil];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXOptionalValue<NSValue *> *)pointFromValue:(id)value error:(NSError **)error
{
  @try {
    CGPoint geometry = CGPointZero;
    BOOL valid = NO;
    if ([value isKindOfClass:NSValue.class]) {
      if (strcmp([value objCType], @encode(CGPoint)) == 0) {
        [value getValue:&geometry size:sizeof(geometry)];
        valid = YES;
      }
    } else {
      valid = [_runtime getPoint:&geometry fromValue:value];
    }
    return [[FBAXOptionalValue alloc] initWithValue:valid ? [NSValue valueWithBytes:&geometry objCType:@encode(CGPoint)] : nil];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXOptionalValue<NSString *> *)descriptionOfValue:(id)value error:(NSError **)error
{
  @try {
    return [[FBAXOptionalValue alloc] initWithValue:[value description]];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

- (FBAXOptionalValue<NSString *> *)localizedDescriptionOfError:(NSError *)value error:(NSError **)error
{
  @try {
    return [[FBAXOptionalValue alloc] initWithValue:value.localizedDescription];
  } @catch (NSException *exception) {
    FBAXClientException(exception, error);
    return nil;
  }
}

@end
