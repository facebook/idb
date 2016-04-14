/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorQuery.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorError.h"
#import "FBSimulator.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorConfigurationVariants.h"
#import "FBSimulatorPredicates.h"
#import "FBSimulator+Helpers.h"

@implementation FBSimulatorQuery

#pragma mark Initializers

- (instancetype)init
{
  return [self initWithUDIDs:NSSet.new states:NSSet.new osVersions:NSSet.new devices:NSSet.new range:NSMakeRange(NSNotFound, 0)];
}

- (instancetype)initWithUDIDs:(NSSet<NSString *> *)udids states:(NSSet<NSNumber *> *)states osVersions:(NSSet<id<FBSimulatorConfiguration_OS>> *)osVersions devices:(NSSet<id<FBSimulatorConfiguration_Device>> *)devices range:(NSRange)range
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

+ (instancetype)states:(NSArray<NSNumber *> *)states
{
  return [self.allSimulators states:states];
}

- (instancetype)states:(NSArray<NSNumber *> *)states
{
  if (states.count == 0) {
    return self;
  }

  return [[self.class alloc] initWithUDIDs:self.udids states:[self.states setByAddingObjectsFromArray:states] osVersions:self.osVersions devices:self.devices range:self.range];
}

+ (instancetype)osVersions:(NSArray<id<FBSimulatorConfiguration_OS>> *)osVersions
{
  return [self.allSimulators osVersions:osVersions];
}

- (instancetype)osVersions:(NSArray<id<FBSimulatorConfiguration_OS>> *)osVersions
{
  if (osVersions.count == 0) {
    return self;
  }

  return [[self.class alloc] initWithUDIDs:self.udids states:self.states osVersions:[self.osVersions setByAddingObjectsFromArray:osVersions] devices:self.devices range:self.range];
}

+ (instancetype)devices:(NSArray<id<FBSimulatorConfiguration_Device>> *)devices
{
  return [self.allSimulators devices:devices];
}

- (instancetype)devices:(NSArray<id<FBSimulatorConfiguration_Device>> *)devices
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

- (NSArray<FBSimulator *> *)perform:(FBSimulatorSet *)set
{
  NSMutableArray<NSPredicate *> *predicates = [NSMutableArray array];
  if (self.udids.count > 0) {
    [predicates addObject:[FBSimulatorPredicates udids:self.udids.allObjects]];
  }
  if (self.states.count > 0) {
    [predicates addObject:[FBSimulatorPredicates states:self.states.allObjects]];
  }
  if (self.osVersions.count > 0) {
    [predicates addObject:[FBSimulatorPredicates osVersions:self.osVersions.allObjects]];
  }
  if (self.devices.count > 0) {
    [predicates addObject:[FBSimulatorPredicates devices:self.devices.allObjects]];
  }

  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:predicates];
  NSArray<FBSimulator *> *simulators = [set.allSimulators filteredArrayUsingPredicate:predicate];
  if (self.range.location == NSNotFound && self.range.length == 0) {
    return simulators;
  }
  NSRange range = NSIntersectionRange(self.range, NSMakeRange(0, simulators.count - 1));
  return [simulators subarrayWithRange:range];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBSimulatorQuery alloc] initWithUDIDs:self.udids states:self.states osVersions:self.osVersions devices:self.devices range:self.range];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  NSSet<NSString *> *udids = [coder decodeObjectForKey:NSStringFromSelector(@selector(udids))];
  NSSet<NSNumber *> *states = [coder decodeObjectForKey:NSStringFromSelector(@selector(states))];
  NSSet<id<FBSimulatorConfiguration_OS>> *osVersions = [coder decodeObjectForKey:NSStringFromSelector(@selector(osVersions))];
  NSSet<id<FBSimulatorConfiguration_Device>> *devices = [coder decodeObjectForKey:NSStringFromSelector(@selector(devices))];
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
    @"states" : [FBSimulatorQuery stateStringsForStateNumbers:self.states.allObjects],
    @"os_versions" : [FBSimulatorQuery stringsFromOSVersions:self.osVersions.allObjects],
    @"devices" : [FBSimulatorQuery stringsFromDevices:self.devices.allObjects],
    @"range" : NSStringFromRange(self.range),
  };
}

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBSimulatorError describeFormat:@"%@ is not an NSDictionary<NSString, id>", json] fail:error];
  }
  NSArray<NSString *> *udids = json[@"udids"] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:udids withClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"'udids' %@ is not an NSArray<NSString>", udids] fail:error];
  }
  NSArray<NSString *> *stateStrings = json[@"states"] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:udids withClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"'states' %@ is not an NSArray<NSString>", udids] fail:error];
  }
  NSArray<NSNumber *> *stateNumbers = [FBSimulatorQuery stateNumbersForStateStrings:stateStrings];
  NSArray<NSString *> *osVersionStrings = json[@"os_versions"] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:osVersionStrings withClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"'os_versions' %@ is not an NSArray<NSString>", udids] fail:error];
  }
  NSArray<id<FBSimulatorConfiguration_OS>> *osVersions = [FBSimulatorQuery osVersionsFromStrings:osVersionStrings];
  NSArray<NSString *> *devicesStrings = json[@"devices"] ?: @[];
  if (![FBCollectionInformation isArrayHeterogeneous:osVersionStrings withClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"'devices' %@ is not an NSArray<NSString>", udids] fail:error];
  }
  NSArray<id<FBSimulatorConfiguration_Device>> *devices = [FBSimulatorQuery devicesFromStrings:devicesStrings];

  NSString *rangeString = json[@"range"];
  if (![rangeString isKindOfClass:NSString.class]) {
    return [[FBSimulatorError describeFormat:@"'range' %@ is not an NSString", rangeString] fail:error];
  }
  NSRange range = NSRangeFromString(rangeString);
  if (range.location == 0 && range.length == 0) {
    range = NSMakeRange(NSNotFound, 0);
  }

  return [[FBSimulatorQuery alloc]
    initWithUDIDs:[NSSet setWithArray:udids]
    states:[NSSet setWithArray:stateNumbers]
    osVersions:[NSSet setWithArray:osVersions]
    devices:[NSSet setWithArray:devices]
    range:range];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBSimulatorQuery *)query
{
  if (![query isKindOfClass:self.class]) {
    return NO;
  }

  return [self.udids isEqualToSet:query.udids] &&
         [self.states isEqualToSet:query.states] &&
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
    [FBCollectionInformation oneLineDescriptionFromArray:[FBSimulatorQuery stateStringsForStateNumbers:self.states.allObjects]],
    [FBCollectionInformation oneLineDescriptionFromArray:self.devices.allObjects],
    [FBCollectionInformation oneLineDescriptionFromArray:self.osVersions.allObjects],
    NSStringFromRange(self.range)
  ];
}

#pragma mark Private

+ (NSArray<NSString *> *)stateStringsForStateNumbers:(NSArray<NSNumber *> *)stateNumbers
{
  NSMutableArray<NSString *> *stateStrings = [NSMutableArray array];
  for (NSNumber *number in stateNumbers) {
    FBSimulatorState state = (FBSimulatorState) number.unsignedIntegerValue;
    NSString *string = [FBSimulator stateStringFromSimulatorState:state].lowercaseString;
    [stateStrings addObject:string];
  }
  return [stateStrings copy];
}

+ (NSArray<NSNumber *> *)stateNumbersForStateStrings:(NSArray<NSString *> *)stateStrings
{
  NSMutableArray<NSNumber *> *stateNumbers = [NSMutableArray array];
  for (NSString *stateString in stateStrings) {
    FBSimulatorState state = [FBSimulator simulatorStateFromStateString:stateString];
    [stateNumbers addObject:@(state)];
  }
  return stateNumbers;
}

+ (NSArray<id<FBSimulatorConfiguration_OS>> *)osVersionsFromStrings:(NSArray<NSString *> *)strings
{
  NSMutableArray<id<FBSimulatorConfiguration_OS>> *osVersions = [NSMutableArray array];
  for (NSString *string in strings) {
    id<FBSimulatorConfiguration_OS> osVersion = FBSimulatorConfigurationVariants.nameToOSVersion[string];
    if (!osVersion) {
      continue;
    }
    [osVersions addObject:osVersion];
  }
  return [osVersions copy];
}

+ (NSArray<NSString *> *)stringsFromOSVersions:(NSArray<id<FBSimulatorConfiguration_OS>> *)osVersions
{
  return [osVersions valueForKey:@"name"];
}

+ (NSArray<id<FBSimulatorConfiguration_Device>> *)devicesFromStrings:(NSArray<NSString *> *)strings
{
  NSMutableArray<id<FBSimulatorConfiguration_Device>> *devices = [NSMutableArray array];
  for (NSString *string in strings) {
    id<FBSimulatorConfiguration_Device> device = FBSimulatorConfigurationVariants.nameToDevice[string];
    if (!device) {
      continue;
    }
    [devices addObject:device];
  }
  return [devices copy];
}

+ (NSArray<NSString *> *)stringsFromDevices:(NSArray<id<FBSimulatorConfiguration_Device>> *)devices
{
  return [devices valueForKey:@"deviceName"];
}

@end
