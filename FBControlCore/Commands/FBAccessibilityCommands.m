/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAccessibilityCommands.h"

// Accessibility dictionary keys
FBAXKeys const FBAXKeysLabel = @"AXLabel";
FBAXKeys const FBAXKeysFrame = @"AXFrame";
FBAXKeys const FBAXKeysValue = @"AXValue";
FBAXKeys const FBAXKeysUniqueID = @"AXUniqueId";
FBAXKeys const FBAXKeysType = @"type";
FBAXKeys const FBAXKeysTitle = @"title";
FBAXKeys const FBAXKeysFrameDict = @"frame";
FBAXKeys const FBAXKeysHelp = @"help";
FBAXKeys const FBAXKeysEnabled = @"enabled";
FBAXKeys const FBAXKeysCustomActions = @"custom_actions";
FBAXKeys const FBAXKeysRole = @"role";
FBAXKeys const FBAXKeysRoleDescription = @"role_description";
FBAXKeys const FBAXKeysSubrole = @"subrole";
FBAXKeys const FBAXKeysContentRequired = @"content_required";
FBAXKeys const FBAXKeysPID = @"pid";
FBAXKeys const FBAXKeysTraits = @"traits";
FBAXKeys const FBAXKeysExpanded = @"expanded";
FBAXKeys const FBAXKeysPlaceholder = @"placeholder";
FBAXKeys const FBAXKeysHidden = @"hidden";
FBAXKeys const FBAXKeysFocused = @"focused";
FBAXKeys const FBAXKeysIsRemote = @"is_remote";

NSSet<FBAXKeys> *FBAXKeysDefaultSet(void) {
  static NSSet<FBAXKeys> *defaultSet;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    defaultSet = [NSSet setWithArray:@[
      FBAXKeysLabel, FBAXKeysFrame, FBAXKeysValue, FBAXKeysUniqueID,
      FBAXKeysType, FBAXKeysTitle, FBAXKeysFrameDict, FBAXKeysHelp,
      FBAXKeysEnabled, FBAXKeysCustomActions, FBAXKeysRole,
      FBAXKeysRoleDescription, FBAXKeysSubrole, FBAXKeysContentRequired,
      FBAXKeysPID, FBAXKeysTraits,
    ]];
  });
  return defaultSet;
}

@implementation FBAccessibilityRequestOptions

+ (instancetype)defaultOptions
{
  return [[self alloc] init];
}

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _nestedFormat = NO;
  _keys = FBAXKeysDefaultSet();
  _enableLogging = NO;
  _enableProfiling = NO;

  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  FBAccessibilityRequestOptions *copy = [[FBAccessibilityRequestOptions alloc] init];
  copy.nestedFormat = self.nestedFormat;
  copy.keys = [self.keys copy];
  copy.enableLogging = self.enableLogging;
  copy.enableProfiling = self.enableProfiling;
  copy.collectFrameCoverage = self.collectFrameCoverage;
  return copy;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"<%@: nested=%@, keys=%@, logging=%@, profiling=%@, collectFrameCoverage=%@>",
          NSStringFromClass(self.class),
          self.nestedFormat ? @"YES" : @"NO",
          self.keys,
          self.enableLogging ? @"YES" : @"NO",
          self.enableProfiling ? @"YES" : @"NO",
          self.collectFrameCoverage ? @"YES" : @"NO"];
}

@end

@implementation FBAccessibilityProfilingData

- (instancetype)initWithElementCount:(int64_t)elementCount
                  attributeFetchCount:(int64_t)attributeFetchCount
                         xpcCallCount:(int64_t)xpcCallCount
                  translationDuration:(CFAbsoluteTime)translationDuration
            elementConversionDuration:(CFAbsoluteTime)elementConversionDuration
               serializationDuration:(CFAbsoluteTime)serializationDuration
                     totalXPCDuration:(CFAbsoluteTime)totalXPCDuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _elementCount = elementCount;
  _attributeFetchCount = attributeFetchCount;
  _xpcCallCount = xpcCallCount;
  _translationDuration = translationDuration;
  _elementConversionDuration = elementConversionDuration;
  _serializationDuration = serializationDuration;
  _totalXPCDuration = totalXPCDuration;

  return self;
}

- (NSDictionary<NSString *, NSNumber *> *)asDictionary
{
  return @{
    @"element_count": @(self.elementCount),
    @"attribute_fetch_count": @(self.attributeFetchCount),
    @"xpc_call_count": @(self.xpcCallCount),
    @"translation_duration_ms": @(self.translationDuration * 1000),
    @"element_conversion_duration_ms": @(self.elementConversionDuration * 1000),
    @"serialization_duration_ms": @(self.serializationDuration * 1000),
    @"total_xpc_duration_ms": @(self.totalXPCDuration * 1000),
  };
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"<%@: elements=%lld, xpc_calls=%lld, translation=%.2fms, serialization=%.2fms>",
          NSStringFromClass(self.class),
          self.elementCount,
          self.xpcCallCount,
          self.translationDuration * 1000,
          self.serializationDuration * 1000];
}

@end

@implementation FBAccessibilityElementsResponse

- (instancetype)initWithElements:(id)elements
                   profilingData:(nullable FBAccessibilityProfilingData *)profilingData
                   frameCoverage:(nullable NSNumber *)frameCoverage
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _elements = elements;
  _profilingData = profilingData;
  _frameCoverage = frameCoverage;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"<%@: elements=%@, profiling=%@, frameCoverage=%@>",
          NSStringFromClass(self.class),
          [self.elements class],
          self.profilingData,
          self.frameCoverage];
}

@end
