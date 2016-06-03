/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSTargetQuery.h"

#import "FBiOSTarget.h"
#import "FBControlCoreError.h"
#import "FBCollectionInformation.h"
#import "FBControlCoreConfigurationVariants.h"

@implementation FBiOSTargetQuery

#pragma mark Initializers

- (instancetype)init
{
  return [self initWithUDIDs:NSSet.new states:NSIndexSet.new osVersions:NSSet.new devices:NSSet.new range:NSMakeRange(NSNotFound, 0)];
}

- (instancetype)initWithUDIDs:(NSSet<NSString *> *)udids states:(NSIndexSet *)states osVersions:(NSSet<id<FBControlCoreConfiguration_OS>> *)osVersions devices:(NSSet<id<FBControlCoreConfiguration_Device>> *)devices range:(NSRange)range
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _udids = udids;
  _states = states;
  _osVersions = osVersions;
  _devices = devices;
  _range = range;

  return self;
}

#pragma mark Public

+ (instancetype)allSimulators
{
  return [self new];
}

+ (instancetype)udids:(NSArray<NSString *> *)udids
{
  return [self.allSimulators udids:udids];
}

- (instancetype)udids:(NSArray<NSString *> *)udids
{
  if (udids.count == 0) {
    return self;
  }

  return [[self.class alloc] initWithUDIDs:[self.udids setByAddingObjectsFromArray:udids] states:self.states osVersions:self.osVersions devices:self.devices range:self.range];
}

+ (instancetype)states:(NSIndexSet *)states
{
  return [self.allSimulators states:states];
}

- (instancetype)states:(NSIndexSet *)states
{
  if (states.count == 0) {
    return self;
  }

  NSMutableIndexSet *indexSet = [self.states mutableCopy];
  [indexSet addIndexes:states];
  return [[self.class alloc] initWithUDIDs:self.udids states:[indexSet copy] osVersions:self.osVersions devices:self.devices range:self.range];
}

+ (instancetype)osVersions:(NSArray<id<FBControlCoreConfiguration_OS>> *)osVersions
{
  return [self.allSimulators osVersions:osVersions];
}

- (instancetype)osVersions:(NSArray<id<FBControlCoreConfiguration_OS>> *)osVersions
{
  if (osVersions.count == 0) {
    return self;
  }

  return [[self.class alloc] initWithUDIDs:self.udids states:self.states osVersions:[self.osVersions setByAddingObjectsFromArray:osVersions] devices:self.devices range:self.range];
}

+ (instancetype)devices:(NSArray<id<FBControlCoreConfiguration_Device>> *)devices
{
  return [self.allSimulators devices:devices];
}

- (instancetype)devices:(NSArray<id<FBControlCoreConfiguration_Device>> *)devices
{
  if (devices.count == 0) {
    return self;
  }

  return [[self.class alloc] initWithUDIDs:self.udids states:self.states osVersions:self.osVersions devices:[self.devices setByAddingObjectsFromArray:devices] range:self.range];
}

+ (instancetype)range:(NSRange)range
{
  return [self.allSimulators range:range];
}

- (instancetype)range:(NSRange)range
{
  if (range.location == NSNotFound && range.length == 0) {
    return self;
  }

  return [[self.class alloc] initWithUDIDs:self.udids states:self.states osVersions:self.osVersions devices:self.devices range:range];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBiOSTargetQuery alloc] initWithUDIDs:self.udids states:self.states osVersions:self.osVersions devices:self.devices range:self.range];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  NSSet<NSString *> *udids = [coder decodeObjectForKey:NSStringFromSelector(@selector(udids))];
  NSIndexSet *states = [coder decodeObjectForKey:NSStringFromSelector(@selector(states))];
  NSSet<id<FBControlCoreConfiguration_OS>> *osVersions = [coder decodeObjectForKey:NSStringFromSelector(@selector(osVersions))];
  NSSet<id<FBControlCoreConfiguration_Device>> *devices = [coder decodeObjectForKey:NSStringFromSelector(@selector(devices))];
  NSRange range = [[coder decodeObjectForKey:NSStringFromSelector(@selector(range))] rangeValue];
  return [self initWithUDIDs:udids states:states osVersions:osVersions devices:devices range:range];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.udids forKey:NSStringFromSelector(@selector(udids))];
  [coder encodeObject:self.states forKey:NSStringFromSelector(@selector(states))];
  [coder encodeObject:self.osVersions forKey:NSStringFromSelector(@selector(osVersions))];
  [coder encodeObject:self.devices forKey:NSStringFromSelector(@selector(devices))];
  [coder encodeObject:[NSValue valueWithRange:self.range] forKey:NSStringFromSelector(@selector(range))];
}

#pragma mark JSON

- (id)jsonSerializableRepresentation
{
  return @{
    @"udids" : self.udids.allObjects,
    @"states" : [FBiOSTargetQuery stateStringsForStateIndeces:self.states],
    @"os_versions" : [FBiOSTargetQuery stringsFromOSVersions:self.osVersions.allObjects],
    @"devices" : [FBiOSTargetQuery stringsFromDevices:self.devices.allObjects],
    @"range" : NSStringFromRange(self.range),
  };
}

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not an NSDictionary<NSString, id>", json] fail:error];
  }
  NSArray<NSString *> *udids = json[@"udids"] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:udids withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'udids' %@ is not an NSArray<NSString>", udids] fail:error];
  }
  NSArray<NSString *> *stateStrings = json[@"states"] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:udids withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'states' %@ is not an NSArray<NSString>", udids] fail:error];
  }
  NSIndexSet *stateIndeces = [FBiOSTargetQuery stateIndecesForStateStrings:stateStrings];
  NSArray<NSString *> *osVersionStrings = json[@"os_versions"] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:osVersionStrings withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'os_versions' %@ is not an NSArray<NSString>", udids] fail:error];
  }
  NSArray<id<FBControlCoreConfiguration_OS>> *osVersions = [FBiOSTargetQuery osVersionsFromStrings:osVersionStrings];
  NSArray<NSString *> *devicesStrings = json[@"devices"] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:osVersionStrings withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'devices' %@ is not an NSArray<NSString>", udids] fail:error];
  }
  NSArray<id<FBControlCoreConfiguration_Device>> *devices = [FBiOSTargetQuery devicesFromStrings:devicesStrings];

  NSString *rangeString = json[@"range"];
  if (![rangeString isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'range' %@ is not an NSString", rangeString] fail:error];
  }
  NSRange range = NSRangeFromString(rangeString);
  if (range.location == 0 && range.length == 0) {
    range = NSMakeRange(NSNotFound, 0);
  }

  return [[FBiOSTargetQuery alloc]
    initWithUDIDs:[NSSet setWithArray:udids]
    states:stateIndeces
    osVersions:[NSSet setWithArray:osVersions]
    devices:[NSSet setWithArray:devices]
    range:range];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBiOSTargetQuery *)query
{
  if (![query isKindOfClass:self.class]) {
    return NO;
  }

  return [self.udids isEqualToSet:query.udids] &&
         [self.states isEqualToIndexSet:query.states] &&
         [self.devices isEqualToSet:query.devices] &&
         [self.osVersions isEqualToSet:query.osVersions] &&
         NSEqualRanges(self.range, query.range);
}

- (NSUInteger)hash
{
  return self.udids.hash ^ self.states.hash ^ self.devices.hash ^ self.osVersions.hash ^ self.range.length ^ self.range.location;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"UDIDs %@ | States %@ | Devices %@ | OS Versions %@ | Range %@",
    [FBCollectionInformation oneLineDescriptionFromArray:self.udids.allObjects],
    [FBCollectionInformation oneLineDescriptionFromArray:[FBiOSTargetQuery stateStringsForStateIndeces:self.states]],
    [FBCollectionInformation oneLineDescriptionFromArray:self.devices.allObjects],
    [FBCollectionInformation oneLineDescriptionFromArray:self.osVersions.allObjects],
    NSStringFromRange(self.range)
  ];
}

#pragma mark Private

+ (NSArray<NSString *> *)stateStringsForStateIndeces:(NSIndexSet *)stateIndeces
{
  NSMutableArray<NSString *> *stateStrings = [NSMutableArray array];
  [stateIndeces enumerateIndexesUsingBlock:^(NSUInteger state, BOOL *_Nonnull stop) {
    NSString *string = FBSimulatorStateStringFromState(state).lowercaseString;
    [stateStrings addObject:string];
  }];
  return [stateStrings copy];
}

+ (NSIndexSet *)stateIndecesForStateStrings:(NSArray<NSString *> *)stateStrings
{
  NSMutableIndexSet *stateIndeces = [NSMutableIndexSet indexSet];
  for (NSString *stateString in stateStrings) {
    FBSimulatorState state = FBSimulatorStateFromStateString(stateString);
    [stateIndeces addIndex:(NSUInteger)state];
  }
  return stateIndeces;
}

+ (NSArray<id<FBControlCoreConfiguration_OS>> *)osVersionsFromStrings:(NSArray<NSString *> *)strings
{
  NSMutableArray<id<FBControlCoreConfiguration_OS>> *osVersions = [NSMutableArray array];
  for (NSString *string in strings) {
    id<FBControlCoreConfiguration_OS> osVersion = FBControlCoreConfigurationVariants.nameToOSVersion[string];
    if (!osVersion) {
      continue;
    }
    [osVersions addObject:osVersion];
  }
  return [osVersions copy];
}

+ (NSArray<NSString *> *)stringsFromOSVersions:(NSArray<id<FBControlCoreConfiguration_OS>> *)osVersions
{
  return [osVersions valueForKey:@"name"];
}

+ (NSArray<id<FBControlCoreConfiguration_Device>> *)devicesFromStrings:(NSArray<NSString *> *)strings
{
  NSMutableArray<id<FBControlCoreConfiguration_Device>> *devices = [NSMutableArray array];
  for (NSString *string in strings) {
    id<FBControlCoreConfiguration_Device> device = FBControlCoreConfigurationVariants.nameToDevice[string];
    if (!device) {
      continue;
    }
    [devices addObject:device];
  }
  return [devices copy];
}

+ (NSArray<NSString *> *)stringsFromDevices:(NSArray<id<FBControlCoreConfiguration_Device>> *)devices
{
  return [devices valueForKey:@"deviceName"];
}

@end
