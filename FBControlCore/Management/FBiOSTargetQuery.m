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
#import "FBiOSTargetPredicates.h"

@implementation FBiOSTargetQuery

#pragma mark Initializers

- (instancetype)init
{
  return [self initWithUDIDs:NSSet.new states:NSIndexSet.new architectures:NSSet.new targetType:FBiOSTargetTypeAll osVersions:NSSet.new devices:NSSet.new range:NSMakeRange(NSNotFound, 0)];
}

- (instancetype)initWithUDIDs:(NSSet<NSString *> *)udids states:(NSIndexSet *)states architectures:(NSSet<FBArchitecture> *)architectures targetType:(FBiOSTargetType)targetType osVersions:(NSSet<FBOSVersionName> *)osVersions devices:(NSSet<FBDeviceModel> *)devices range:(NSRange)range
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _udids = udids;
  _states = states;
  _architectures = architectures;
  _targetType = targetType;
  _osVersions = osVersions;
  _devices = devices;
  _range = range;

  return self;
}

#pragma mark Public

+ (instancetype)allTargets
{
  return [self new];
}

+ (instancetype)udids:(NSArray<NSString *> *)udids
{
  return [self.allTargets udids:udids];
}

- (instancetype)udids:(NSArray<NSString *> *)udids
{
  if (udids.count == 0) {
    return self;
  }

  return [[self.class alloc] initWithUDIDs:[self.udids setByAddingObjectsFromArray:udids] states:self.states architectures:self.architectures targetType:self.targetType osVersions:self.osVersions devices:self.devices range:self.range];
}

+ (instancetype)states:(NSIndexSet *)states
{
  return [self.allTargets states:states];
}

- (instancetype)states:(NSIndexSet *)states
{
  if (states.count == 0) {
    return self;
  }

  NSMutableIndexSet *indexSet = [self.states mutableCopy];
  [indexSet addIndexes:states];
  return [[self.class alloc] initWithUDIDs:self.udids states:[indexSet copy] architectures:self.architectures targetType:self.targetType osVersions:self.osVersions devices:self.devices range:self.range];
}

+ (instancetype)architectures:(NSArray<FBArchitecture> *)architectures {
  return [self.allTargets architectures:architectures];
}

- (instancetype)architectures:(NSArray<FBArchitecture> *)architectures {
  if (architectures.count == 0) {
    return self;
  }

  return [[self.class alloc] initWithUDIDs:self.udids states:self.states architectures:[self.architectures setByAddingObjectsFromArray:architectures] targetType:self.targetType osVersions:self.osVersions devices:self.devices range:self.range];
}

+ (instancetype)targetType:(FBiOSTargetType)targetType
{
  return [self.allTargets targetType:targetType];
}

- (instancetype)targetType:(FBiOSTargetType)targetType
{
  return [[self.class alloc] initWithUDIDs:self.udids states:self.states architectures:self.architectures targetType:targetType osVersions:self.osVersions devices:self.devices range:self.range];
}

+ (instancetype)osVersions:(NSArray<FBOSVersionName> *)osVersions
{
  return [self.allTargets osVersions:osVersions];
}

- (instancetype)osVersions:(NSArray<FBOSVersionName> *)osVersions
{
  if (osVersions.count == 0) {
    return self;
  }

  return [[self.class alloc] initWithUDIDs:self.udids states:self.states architectures:self.architectures targetType:self.targetType osVersions:[self.osVersions setByAddingObjectsFromArray:osVersions] devices:self.devices range:self.range];
}

+ (instancetype)devices:(NSArray<FBDeviceModel> *)devices
{
  return [self.allTargets devices:devices];
}

- (instancetype)devices:(NSArray<FBDeviceModel> *)devices
{
  if (devices.count == 0) {
    return self;
  }

  return [[self.class alloc] initWithUDIDs:self.udids states:self.states architectures:self.architectures targetType:self.targetType osVersions:self.osVersions devices:[self.devices setByAddingObjectsFromArray:devices] range:self.range];
}

+ (instancetype)range:(NSRange)range
{
  return [self.allTargets range:range];
}

- (instancetype)range:(NSRange)range
{
  if (range.location == NSNotFound && range.length == 0) {
    return self;
  }

  return [[self.class alloc] initWithUDIDs:self.udids states:self.states architectures:self.architectures targetType:self.targetType osVersions:self.osVersions devices:self.devices range:range];
}

- (NSArray<id<FBiOSTarget>> *)filter:(NSArray<id<FBiOSTarget>> *)targets
{
  NSMutableArray<NSPredicate *> *predicates = [NSMutableArray array];
  [predicates addObject:[FBiOSTargetPredicates targetType:self.targetType]];
  if (self.udids.count > 0) {
    [predicates addObject:[FBiOSTargetPredicates udids:self.udids.allObjects]];
  }
  if (self.states.count > 0) {
    [predicates addObject:[FBiOSTargetPredicates states:self.states]];
  }
  if (self.architectures.count > 0) {
    [predicates addObject:[FBiOSTargetPredicates architectures:self.architectures.allObjects]];
  }
  if (self.osVersions.count > 0) {
    [predicates addObject:[FBiOSTargetPredicates osVersions:self.osVersions.allObjects]];
  }
  if (self.devices.count > 0) {
    [predicates addObject:[FBiOSTargetPredicates devices:self.devices.allObjects]];
  }

  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:predicates];
  targets = [targets filteredArrayUsingPredicate:predicate];
  if (self.range.location == NSNotFound && self.range.length == 0) {
    return targets;
  }
  NSRange range = NSIntersectionRange(self.range, NSMakeRange(0, targets.count));
  return [targets subarrayWithRange:range];
}

- (BOOL)excludesAll:(FBiOSTargetType)targetType
{
  return (self.targetType & targetType) == FBiOSTargetTypeNone;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBiOSTargetQuery alloc] initWithUDIDs:self.udids states:self.states architectures:self.architectures targetType:self.targetType osVersions:self.osVersions devices:self.devices range:self.range];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  NSSet<NSString *> *udids = [coder decodeObjectForKey:NSStringFromSelector(@selector(udids))];
  NSIndexSet *states = [coder decodeObjectForKey:NSStringFromSelector(@selector(states))];
  NSSet<NSString *> *architectures = [coder decodeObjectForKey:NSStringFromSelector(@selector(architectures))];
  FBiOSTargetType targetType = [[coder decodeObjectForKey:NSStringFromSelector(@selector(targetType))] unsignedIntegerValue];
  NSSet<FBOSVersionName> *osVersions = [coder decodeObjectForKey:NSStringFromSelector(@selector(osVersions))];
  NSSet<FBDeviceModel> *devices = [coder decodeObjectForKey:NSStringFromSelector(@selector(devices))];
  NSRange range = [[coder decodeObjectForKey:NSStringFromSelector(@selector(range))] rangeValue];
  return [self initWithUDIDs:udids states:states architectures:architectures targetType:targetType osVersions:osVersions devices:devices range:range];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.udids forKey:NSStringFromSelector(@selector(udids))];
  [coder encodeObject:self.states forKey:NSStringFromSelector(@selector(states))];
  [coder encodeObject:self.architectures forKey:NSStringFromSelector(@selector(architectures))];
  [coder encodeObject:@(self.targetType) forKey:NSStringFromSelector(@selector(targetType))];
  [coder encodeObject:self.osVersions forKey:NSStringFromSelector(@selector(osVersions))];
  [coder encodeObject:self.devices forKey:NSStringFromSelector(@selector(devices))];
  [coder encodeObject:[NSValue valueWithRange:self.range] forKey:NSStringFromSelector(@selector(range))];
}

#pragma mark JSON

static NSString *const KeyUDIDs = @"udids";
static NSString *const KeyStates = @"states";
static NSString *const KeyArchitectures = @"architectures";
static NSString *const KeyTargetTypes = @"target_types";
static NSString *const KeyOSVersions = @"os_versions";
static NSString *const KeyDevices = @"devices";
static NSString *const KeyRange = @"range";

- (id)jsonSerializableRepresentation
{
  return @{
    KeyUDIDs : self.udids.allObjects,
    KeyStates : [FBiOSTargetQuery stateStringsForStateIndeces:self.states],
    KeyArchitectures : self.architectures.allObjects,
    KeyTargetTypes : FBiOSTargetTypeStringsFromTargetType(self.targetType),
    KeyOSVersions : self.osVersions.allObjects,
    KeyDevices : self.devices.allObjects,
    KeyRange : NSStringFromRange(self.range),
  };
}

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not an NSDictionary<NSString, id>", json] fail:error];
  }
  NSArray<NSString *> *udids = json[KeyUDIDs] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:udids withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'%@' %@ is not an NSArray<NSString>", KeyUDIDs, udids] fail:error];
  }
  NSArray<NSString *> *stateStrings = json[KeyStates] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:udids withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'%@' %@ is not an NSArray<NSString>", KeyStates, udids] fail:error];
  }
  NSArray<NSString *> *architectures = json[KeyArchitectures] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:architectures withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'%@' %@ is not an NSArray<NSString>", KeyArchitectures, architectures] fail:error];
  }
  NSArray<NSString *> *targetTypeStrings = json[KeyTargetTypes] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:targetTypeStrings withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'%@' %@ is not an NSArray<NSString>", KeyTargetTypes, targetTypeStrings] fail:error];
  }
  FBiOSTargetType targetType = FBiOSTargetTypeFromTargetTypeStrings(targetTypeStrings);

  NSIndexSet *stateIndeces = [FBiOSTargetQuery stateIndecesForStateStrings:stateStrings];
  NSArray<NSString *> *osVersionStrings = json[KeyOSVersions] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:osVersionStrings withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'%@' %@ is not an NSArray<NSString>", KeyOSVersions, udids] fail:error];
  }
  NSArray<FBOSVersionName> *osVersions = [FBiOSTargetQuery osVersionsFromStrings:osVersionStrings];
  NSArray<NSString *> *devicesStrings = json[KeyDevices] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:osVersionStrings withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'%@' %@ is not an NSArray<NSString>", KeyDevices, udids] fail:error];
  }
  NSArray<FBDeviceModel> *devices = [FBiOSTargetQuery devicesFromStrings:devicesStrings];

  NSString *rangeString = json[KeyRange];
  if (![rangeString isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"'%@' %@ is not an NSString", KeyRange, rangeString] fail:error];
  }
  NSRange range = NSRangeFromString(rangeString);
  if (range.location == 0 && range.length == 0) {
    range = NSMakeRange(NSNotFound, 0);
  }

  return [[FBiOSTargetQuery alloc]
    initWithUDIDs:[NSSet setWithArray:udids]
    states:stateIndeces
    architectures:[NSSet setWithArray:architectures]
    targetType:targetType
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
         [self.architectures isEqualToSet:query.architectures] &&
         self.targetType == query.targetType &&
         [self.devices isEqualToSet:query.devices] &&
         [self.osVersions isEqualToSet:query.osVersions] &&
         NSEqualRanges(self.range, query.range);
}

- (NSUInteger)hash
{
  return self.udids.hash ^ self.states.hash ^ self.architectures.hash ^ self.targetType ^ self.devices.hash ^ self.osVersions.hash ^ self.range.length ^ self.range.location;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"UDIDs %@ | States %@ | Architectures %@ | Target Types %@ | Devices %@ | OS Versions %@ | Range %@",
    [FBCollectionInformation oneLineDescriptionFromArray:self.udids.allObjects],
    [FBCollectionInformation oneLineDescriptionFromArray:[FBiOSTargetQuery stateStringsForStateIndeces:self.states]],
    [FBCollectionInformation oneLineDescriptionFromArray:self.architectures.allObjects],
    [FBCollectionInformation oneLineDescriptionFromArray:FBiOSTargetTypeStringsFromTargetType(self.targetType)],
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

+ (NSArray<FBOSVersionName> *)osVersionsFromStrings:(NSArray<NSString *> *)strings
{
  NSMutableArray<FBOSVersionName> *osVersions = [NSMutableArray array];
  for (NSString *string in strings) {
    FBOSVersion *osVersion = FBControlCoreConfigurationVariants.nameToOSVersion[string];
    if (!osVersion) {
      continue;
    }
    [osVersions addObject:string];
  }
  return [osVersions copy];
}

+ (NSArray<FBDeviceModel> *)devicesFromStrings:(NSArray<NSString *> *)strings
{
  NSMutableArray<FBDeviceModel> *devices = [NSMutableArray array];
  for (NSString *string in strings) {
    FBDeviceType *device = FBControlCoreConfigurationVariants.nameToDevice[string];
    if (!device) {
      continue;
    }
    [devices addObject:string];
  }
  return [devices copy];
}

+ (NSArray<NSString *> *)stringsFromDevices:(NSArray<FBDeviceType *> *)devices
{
  return [devices valueForKey:@"deviceName"];
}

@end
