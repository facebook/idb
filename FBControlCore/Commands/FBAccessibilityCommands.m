/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAccessibilityCommands.h"

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

- (instancetype)initWithElements:(id)elements profilingData:(nullable FBAccessibilityProfilingData *)profilingData
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _elements = elements;
  _profilingData = profilingData;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"<%@: elements=%@, profiling=%@>",
          NSStringFromClass(self.class),
          [self.elements class],
          self.profilingData];
}

@end
