/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorAccessibilityCommands.h"

#import <objc/runtime.h>

#import <CoreSimulator/SimDevice.h>
#import <AccessibilityPlatformTranslation/AXPTranslator.h>
#import <AccessibilityPlatformTranslation/AXPTranslationObject.h>
#import <AccessibilityPlatformTranslation/AXPTranslatorResponse.h>
#import <AccessibilityPlatformTranslation/AXPTranslatorRequest.h>
#import <AccessibilityPlatformTranslation/AXPMacPlatformElement.h>
#import <ApplicationServices/ApplicationServices.h>

#import "FBSimulator.h"
#import "FBSimulatorControlFrameworkLoader.h"
#import "FBSimulatorError.h"

#import <FBControlCore/FBAccessibilityTraits.h>

#import <stdatomic.h>
#import <unistd.h>

static NSString *FBAXErrorDescription(AXError err)
{
  switch (err) {
    case kAXErrorSuccess:
      return @"kAXErrorSuccess";
    case kAXErrorFailure:
      return @"kAXErrorFailure";
    case kAXErrorIllegalArgument:
      return @"kAXErrorIllegalArgument";
    case kAXErrorInvalidUIElement:
      return @"kAXErrorInvalidUIElement";
    case kAXErrorInvalidUIElementObserver:
      return @"kAXErrorInvalidUIElementObserver";
    case kAXErrorCannotComplete:
      return @"kAXErrorCannotComplete";
    case kAXErrorAttributeUnsupported:
      return @"kAXErrorAttributeUnsupported";
    case kAXErrorActionUnsupported:
      return @"kAXErrorActionUnsupported";
    case kAXErrorNotificationUnsupported:
      return @"kAXErrorNotificationUnsupported";
    case kAXErrorNotImplemented:
      return @"kAXErrorNotImplemented";
    case kAXErrorNotificationAlreadyRegistered:
      return @"kAXErrorNotificationAlreadyRegistered";
    case kAXErrorNotificationNotRegistered:
      return @"kAXErrorNotificationNotRegistered";
    case kAXErrorAPIDisabled:
      return @"kAXErrorAPIDisabled";
    case kAXErrorNoValue:
      return @"kAXErrorNoValue";
    case kAXErrorParameterizedAttributeUnsupported:
      return @"kAXErrorParameterizedAttributeUnsupported";
    case kAXErrorNotEnoughPrecision:
      return @"kAXErrorNotEnoughPrecision";
    default:
      return [NSString stringWithFormat:@"AXError(%d)", err];
  }
}

static NSString *FBAXStringAttributeValue(AXUIElementRef element, CFStringRef attribute)
{
  CFTypeRef ref = NULL;
  AXError err = AXUIElementCopyAttributeValue(element, attribute, &ref);
  if (err != kAXErrorSuccess || ref == NULL) {
    return nil;
  }
  if (CFGetTypeID(ref) != CFStringGetTypeID()) {
    CFRelease(ref);
    return nil;
  }
  return (__bridge_transfer NSString *)ref;
}

static BOOL FBAXTitleMatchesDeviceName(AXUIElementRef element, NSString *deviceName)
{
  if (deviceName.length == 0) {
    return YES;
  }
  NSString *title = FBAXStringAttributeValue(element, kAXTitleAttribute);
  if (title.length > 0 && [title containsString:deviceName]) {
    return YES;
  }
  NSString *label = FBAXStringAttributeValue(element, kAXDescriptionAttribute);
  return label.length > 0 && [label containsString:deviceName];
}

static NSArray<NSString *> *FBCGWindowTitlesForPID(pid_t pid)
{
  CFArrayRef windows = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
  if (windows == NULL) {
    return @[];
  }
  NSMutableArray<NSString *> *titles = [NSMutableArray array];
  for (NSDictionary *info in (__bridge NSArray *)windows) {
    NSNumber *ownerPID = info[(id)kCGWindowOwnerPID];
    if (ownerPID.intValue != pid) {
      continue;
    }
    NSString *name = info[(id)kCGWindowName];
    if (name.length > 0) {
      [titles addObject:name];
    }
  }
  CFRelease(windows);
  return [titles copy];
}

/**
 Mutable collector for profiling data during an accessibility request.
 This is a per-request object that accumulates timing and count data.
 Thread-safe via atomic operations for counters that may be incremented from callbacks.
 */
@interface FBAccessibilityProfilingCollector : NSObject

@property (nonatomic, assign) CFAbsoluteTime translationDuration;
@property (nonatomic, assign) CFAbsoluteTime elementConversionDuration;
@property (nonatomic, assign) CFAbsoluteTime serializationDuration;

- (void)incrementElementCount;
- (void)incrementAttributeFetchCount;
- (void)addXPCCallDuration:(CFAbsoluteTime)duration;
- (int64_t)elementCount;
- (int64_t)attributeFetchCount;
- (int64_t)xpcCallCount;
- (CFAbsoluteTime)totalXPCDuration;
- (FBAccessibilityProfilingData *)finalizeWithSerializationDuration:(CFAbsoluteTime)serializationDuration;

@end

@implementation FBAccessibilityProfilingCollector {
  _Atomic int64_t _elementCount;
  _Atomic int64_t _attributeFetchCount;
  _Atomic int64_t _xpcCallCount;
  _Atomic double _totalXPCDuration;
}

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }
  atomic_store(&_elementCount, 0);
  atomic_store(&_attributeFetchCount, 0);
  atomic_store(&_xpcCallCount, 0);
  atomic_store(&_totalXPCDuration, 0.0);
  return self;
}

- (void)incrementElementCount
{
  atomic_fetch_add(&_elementCount, 1);
}

- (void)incrementAttributeFetchCount
{
  atomic_fetch_add(&_attributeFetchCount, 1);
}

- (void)addXPCCallDuration:(CFAbsoluteTime)duration
{
  atomic_fetch_add(&_xpcCallCount, 1);
  // For atomic double addition, we use compare-and-swap loop
  double oldValue, newValue;
  do {
    oldValue = atomic_load(&_totalXPCDuration);
    newValue = oldValue + duration;
  } while (!atomic_compare_exchange_weak(&_totalXPCDuration, &oldValue, newValue));
}

- (int64_t)elementCount
{
  return atomic_load(&_elementCount);
}

- (int64_t)attributeFetchCount
{
  return atomic_load(&_attributeFetchCount);
}

- (int64_t)xpcCallCount
{
  return atomic_load(&_xpcCallCount);
}

- (CFAbsoluteTime)totalXPCDuration
{
  return atomic_load(&_totalXPCDuration);
}

- (FBAccessibilityProfilingData *)finalizeWithSerializationDuration:(CFAbsoluteTime)serializationDuration
{
  return [[FBAccessibilityProfilingData alloc]
    initWithElementCount:self.elementCount
     attributeFetchCount:self.attributeFetchCount
            xpcCallCount:self.xpcCallCount
     translationDuration:self.translationDuration
   elementConversionDuration:self.elementConversionDuration
      serializationDuration:serializationDuration
            totalXPCDuration:self.totalXPCDuration];
}

@end

//
// # About the implementation of Accessibility within CoreSimulator
//
// Accessibility is bridged via CoreSimulator and the Private Framework AccessibilityPlatformTranslation.
// In Simulator.app, SimulatorKit uses NSView semantics for obtaining information about a Simulator; in FBSimulatorControl we aren't necessarily view-backed.
// As a result we are using a reverse-engineered implementation of how SimulatorKit functions, based on inputs to this API.
//
// For this to work the process is as follows:
// - The AXPTranslator is used to do all of the wiring for providing high-level objects that can be interrogated.
// - To do this AXPTranslator uses delegation for performing the underlying accessibility request.
// - The delegation can be tokenized (optionally)
// - The requests are implemented by bridging to CoreSimulator. This is essentially the glue between high-level Accessibility APIs and CoreSimulator's implementation of them.
// - CoreSimulator doesn't actually implement the Accessibility fetches itself. Instead it calls out to an XPC service that is running inside the Simulator.
// - CoreSimulator's API for doing this fetch is Asynchronous, but AXPTranslator's delegation & fetching is not. To smooth over the gaps we have to wait on the result.
// - The reason for non-async APIs here is that AXMacPlatformElement has lazy property access; over time each of the values that are referenced will be filled out with this delegation.
// - The lazy property access can be seen in the logging here, where the AXPTranslatorRequest has a nice description of the object.
// - Additional methods are required in the delegation, depending on whether there needs to be additional transformation, as is in the case with translating co-ordinate systems.
// - We smooth over the differences in the values returned by calling the appropriate methods on AXMacPlatformElement.
// - To get an idea of what methods are usable, take a look at NSAccessibilityElement which is a supertype of AXMacPlatformElement.
// - The tokenized method appears to be the more recent one. The token isn't significant for us so in this case we can just pass a meaningless token that will be received from all delegate callbacks.
//
// All of the above could be implemented without the delegation system. However, this requires dumping large enums and going much lower in the protocol level.
// Instead having the higher level object, liberated from SimulatorKit (and therefore views) is the best compromise and the lightest touch.
//
// The only exception here is the usage of -[NSAccessibility accessibilityParent] which calls a delegate method with an unknown implementation.
// Since all values are enumerated recursively downwards, this is fine for the time being.
//
// We must also remember to set the `bridgeDelegateToken` on all created `AXPTranslationObject`s.
// This applies to those created by us when the `AXPTranslationObject` as well`AXPMacPlatformElement`'s that are created inside `AccessibilityPlatformTranslation`
// This is needed so that we know which Simulator the request belongs to, since the Translator is a singleton object, we need to be able to de-duplicate here.
//

inline static id ensureJSONSerializable(id obj)
{
  if (obj == nil) {
    return NSNull.null;
  }
  return [NSJSONSerialization isValidJSONObject:@[obj]] ? obj : [obj description];
}

@interface FBSimulatorAccessibilitySerializer : NSObject

@end

@implementation FBSimulatorAccessibilitySerializer

static NSString *const AXPrefix = @"AX";

+ (NSArray<NSString *> *)customActionsFromElement:(AXPMacPlatformElement *)element
{
  NSMutableArray<NSString *> *customActionsTemp = [[NSMutableArray alloc] init];
  for (NSString *name in [element.accessibilityCustomActions valueForKey:@"name"]) {
    [customActionsTemp addObject:ensureJSONSerializable(name)];
  }
  return [customActionsTemp copy];
}

// AXTraits is an iOS-specific bitmask that was available in the old SimulatorBridge implementation.
// Returns nil if traits are not supported (e.g., the element doesn't support the attribute).
// The caller should convert nil to NSNull to indicate traits are unavailable for this element.
+ (nullable NSArray<NSString *> *)traitsFromElement:(AXPMacPlatformElement *)element
{
  if (![element respondsToSelector:@selector(accessibilityAttributeValue:)]) {
    return nil;
  }
  id traitsValue = [element accessibilityAttributeValue:@"AXTraits"];
  if (![traitsValue isKindOfClass:NSNumber.class]) {
    return nil;
  }
  uint64_t bitmask = [(NSNumber *)traitsValue unsignedLongLongValue];
  return AXExtractTraits(bitmask).allObjects;
}

+ (NSArray<NSDictionary<NSString *, id> *> *)recursiveDescriptionFromElement:(AXPMacPlatformElement *)element token:(NSString *)token nestedFormat:(BOOL)nestedFormat keys:(NSSet<NSString *> *)keys collector:(nullable FBAccessibilityProfilingCollector *)collector maxDepth:(NSUInteger)maxDepth
{
  element.translation.bridgeDelegateToken = token;
  pid_t frontmostPid = element.translation.pid;
  if (nestedFormat) {
    return @[[self.class nestedRecursiveDescriptionFromElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid remainingDepth:maxDepth]];
  }
  return [self.class flatRecursiveDescriptionFromElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid remainingDepth:maxDepth];
}

+ (NSDictionary<NSString *, id> *)formattedDescriptionOfElement:(AXPMacPlatformElement *)element token:(NSString *)token nestedFormat:(BOOL)nestedFormat keys:(NSSet<NSString *> *)keys collector:(nullable FBAccessibilityProfilingCollector *)collector maxDepth:(NSUInteger)maxDepth
{
  element.translation.bridgeDelegateToken = token;
  pid_t frontmostPid = element.translation.pid;
  if (nestedFormat) {
    return [self.class nestedRecursiveDescriptionFromElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid remainingDepth:maxDepth];
  }
  return [self.class accessibilityDictionaryForElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid];
}

// The values here are intended to mirror the values in the old SimulatorBridge implementation for compatibility downstream.
+ (NSDictionary<NSString *, id> *)accessibilityDictionaryForElement:(AXPMacPlatformElement *)element token:(NSString *)token keys:(NSSet<FBAXKeys> *)keys collector:(nullable FBAccessibilityProfilingCollector *)collector frontmostPid:(pid_t)frontmostPid
{
  // The token must always be set so that the right callback is called
  element.translation.bridgeDelegateToken = token;

  // Increment element count if collector is present
  if (collector) {
    [collector incrementElementCount];
  }

  // Helper macro to include key with JSON serialization if needed (also increments profiling counter)
  #define INCLUDE_IF_KEY(key, expr) do { \
    if ([keys containsObject:key]) { \
      if (collector) { [collector incrementAttributeFetchCount]; } \
      values[key] = ensureJSONSerializable(expr); \
    } \
  } while (0)

  NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];

  // Frame is always computed since it's used by multiple keys
  if (collector) { [collector incrementAttributeFetchCount]; }
  NSRect frame = element.accessibilityFrame;

  // Role is used by multiple keys and needs processing
  // Check FBAXKeysRole first to assign rawRole, then FBAXKeysType can derive from it
  NSString *role = nil;
  NSString *rawRole = nil;
  if ([keys containsObject:FBAXKeysRole]) {
    if (collector) { [collector incrementAttributeFetchCount]; }
    rawRole = element.accessibilityRole;
    values[FBAXKeysRole] = ensureJSONSerializable(rawRole);
  }
  if ([keys containsObject:FBAXKeysType]) {
    // Fetch rawRole if not already present
    if (rawRole == nil) {
      if (collector) { [collector incrementAttributeFetchCount]; }
      rawRole = element.accessibilityRole;
    }
    // The value returned in accessibilityRole may be prefixed with "AX".
    // If that's the case, then let's strip it to make it like the SimulatorBridge implementation.
    if ([rawRole hasPrefix:AXPrefix]) {
      role = [rawRole substringFromIndex:2];
    } else {
      role = rawRole;
    }
  }

  // Build dictionary with only requested values
  // Legacy values that mirror SimulatorBridge
  INCLUDE_IF_KEY(FBAXKeysLabel, element.accessibilityLabel);
  if ([keys containsObject:FBAXKeysFrame]) {
    values[FBAXKeysFrame] = NSStringFromRect(frame);
  }
  INCLUDE_IF_KEY(FBAXKeysValue, element.accessibilityValue);
  INCLUDE_IF_KEY(FBAXKeysUniqueID, element.accessibilityIdentifier);

  // Synthetic values
  if ([keys containsObject:FBAXKeysType]) {
    values[FBAXKeysType] = ensureJSONSerializable(role);
  }

  // New values
  INCLUDE_IF_KEY(FBAXKeysTitle, element.accessibilityTitle);
  if ([keys containsObject:FBAXKeysFrameDict]) {
    values[FBAXKeysFrameDict] = @{
      @"x": @(frame.origin.x),
      @"y": @(frame.origin.y),
      @"width": @(frame.size.width),
      @"height": @(frame.size.height),
    };
  }
  INCLUDE_IF_KEY(FBAXKeysHelp, element.accessibilityHelp);
  INCLUDE_IF_KEY(FBAXKeysEnabled, @(element.accessibilityEnabled));
  INCLUDE_IF_KEY(FBAXKeysCustomActions, [self.class customActionsFromElement:element]);
  INCLUDE_IF_KEY(FBAXKeysRoleDescription, element.accessibilityRoleDescription);
  INCLUDE_IF_KEY(FBAXKeysSubrole, element.accessibilitySubrole);
  INCLUDE_IF_KEY(FBAXKeysContentRequired, @(element.accessibilityRequired));
  INCLUDE_IF_KEY(FBAXKeysPID, @(element.translation.pid));
  if ([keys containsObject:FBAXKeysTraits]) {
    if (collector) { [collector incrementAttributeFetchCount]; }
    NSArray<NSString *> *traits = [self.class traitsFromElement:element];
    values[FBAXKeysTraits] = traits ?: (id)NSNull.null;
  }

  INCLUDE_IF_KEY(FBAXKeysExpanded, @(element.isAccessibilityExpanded));
  INCLUDE_IF_KEY(FBAXKeysPlaceholder, element.accessibilityPlaceholderValue);
  INCLUDE_IF_KEY(FBAXKeysHidden, @(element.isAccessibilityHidden));
  INCLUDE_IF_KEY(FBAXKeysFocused, @(element.isAccessibilityFocused));
  INCLUDE_IF_KEY(FBAXKeysIsRemote, element.translation.pid != frontmostPid ? @YES : @NO);

  #undef INCLUDE_IF_KEY

  return [values copy];
}

// Some bridged iOS containers (notably the iOS 26 floating tab bar) return an empty
// `accessibilityChildren` even though their tab elements are reachable via alternate
// AX attributes such as `AXChildrenInNavigationOrder`, `AXTabs`, `AXVisibleChildren`,
// `AXSelectedChildren`, or `AXContents`. Mirror Accessibility Inspector's behaviour by
// merging from all of them and deduplicating by element identity (NSObject -isEqual:),
// preserving first-seen order so `accessibilityChildren` stays canonical when populated.
+ (NSArray<AXPMacPlatformElement *> *)mergedAccessibilityChildrenForElement:(AXPMacPlatformElement *)element token:(NSString *)token
{
  static NSArray<NSString *> *altAttributeNames;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    altAttributeNames = @[
      @"AXChildrenInNavigationOrder",
      @"AXTabs",
      @"AXVisibleChildren",
      @"AXSelectedChildren",
      @"AXContents",
    ];
  });

  NSMutableArray<AXPMacPlatformElement *> *merged = [NSMutableArray array];
  NSMutableArray *seen = [NSMutableArray array];

  Class macPlatformElementClass = objc_getClass("AXPMacPlatformElement");
  void (^addAll)(NSArray *) = ^(NSArray *candidates) {
    for (id candidate in candidates) {
      if (macPlatformElementClass && ![candidate isKindOfClass:macPlatformElementClass]) {
        continue;
      }
      AXPMacPlatformElement *child = (AXPMacPlatformElement *)candidate;
      if ([seen indexOfObjectPassingTest:^BOOL(id existing, NSUInteger _, BOOL *stop) {
        return existing == child || [existing isEqual:child];
      }] != NSNotFound) {
        continue;
      }
      [seen addObject:child];
      child.translation.bridgeDelegateToken = token;
      [merged addObject:child];
    }
  };

  addAll(element.accessibilityChildren);
  if (![element respondsToSelector:@selector(accessibilityAttributeValue:)]) {
    return merged;
  }
  for (NSString *name in altAttributeNames) {
    id value = [element accessibilityAttributeValue:name];
    if ([value isKindOfClass:NSArray.class]) {
      addAll((NSArray *)value);
    }
  }
  return merged;
}

// This replicates the non-hierarchical system that was previously present in SimulatorBridge.
// In this case the values of frames must be relative to the root, rather than the parent frame.
//
// `remainingDepth` semantics:
//  - 0 means unlimited recursion (the original behaviour).
//  - 1 means we're at the deepest allowed level: the merged-children fan-out is skipped,
//    so this element is serialized as a leaf with no AXChildren / AXTabs / etc. round-trips.
//  - N >= 2 means recurse into children with `remainingDepth - 1`.
+ (NSArray<NSDictionary<NSString *, id> *> *)flatRecursiveDescriptionFromElement:(AXPMacPlatformElement *)element token:(NSString *)token keys:(NSSet<NSString *> *)keys collector:(nullable FBAccessibilityProfilingCollector *)collector frontmostPid:(pid_t)frontmostPid remainingDepth:(NSUInteger)remainingDepth
{
  NSMutableArray<NSDictionary<NSString *, id> *> *values = NSMutableArray.array;
  [values addObject:[self accessibilityDictionaryForElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid]];
  if (remainingDepth == 1) {
    return values;
  }
  NSUInteger childRemainingDepth = (remainingDepth == 0) ? 0 : remainingDepth - 1;
  for (AXPMacPlatformElement *childElement in [self mergedAccessibilityChildrenForElement:element token:token]) {
    NSArray<NSDictionary<NSString *, id> *> *childValues = [self flatRecursiveDescriptionFromElement:childElement token:token keys:keys collector:collector frontmostPid:frontmostPid remainingDepth:childRemainingDepth];
    [values addObjectsFromArray:childValues];
  }
  return values;
}

+ (NSDictionary<NSString *, id> *)nestedRecursiveDescriptionFromElement:(AXPMacPlatformElement *)element token:(NSString *)token keys:(NSSet<NSString *> *)keys collector:(nullable FBAccessibilityProfilingCollector *)collector frontmostPid:(pid_t)frontmostPid remainingDepth:(NSUInteger)remainingDepth
{
  NSMutableDictionary<NSString *, id> *values = [[self accessibilityDictionaryForElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid] mutableCopy];
  NSMutableArray<NSDictionary<NSString *, id> *> *childrenValues = NSMutableArray.array;
  if (remainingDepth != 1) {
    NSUInteger childRemainingDepth = (remainingDepth == 0) ? 0 : remainingDepth - 1;
    for (AXPMacPlatformElement *childElement in [self mergedAccessibilityChildrenForElement:element token:token]) {
      NSDictionary<NSString *, id> *childValues = [self nestedRecursiveDescriptionFromElement:childElement token:token keys:keys collector:collector frontmostPid:frontmostPid remainingDepth:childRemainingDepth];
      [childrenValues addObject:childValues];
    }
  }
  // Always emit the `children` key so consumers see a stable JSON shape even when depth is exhausted.
  values[@"children"] = childrenValues;
  return values;
}

@end

@interface FBAXTranslationRequest : NSObject

@property (nonatomic, assign, readonly) BOOL nestedFormat;
@property (nonatomic, copy, readonly) NSString *token;
@property (nonatomic, copy, readonly) NSSet<NSString *> *keys;
@property (nonatomic, assign, readonly) NSUInteger maxDepth;
@property (nonatomic, strong, nullable) SimDevice *device;
@property (nonatomic, strong, nullable) FBAccessibilityProfilingCollector *collector;
@property (nonatomic, strong, nullable) id<FBControlCoreLogger> logger;

@end

@implementation FBAXTranslationRequest

- (instancetype)initWithNestedFormat:(BOOL)nestedFormat keys:(NSSet<NSString *> *)keys maxDepth:(NSUInteger)maxDepth
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _token = NSUUID.UUID.UUIDString;
  _nestedFormat = nestedFormat;
  _keys = [keys copy];
  _maxDepth = maxDepth;

  return self;
}

- (AXPTranslationObject *)performWithTranslator:(AXPTranslator *)translator
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (nullable id)serialize:(AXPMacPlatformElement *)element error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (instancetype)cloneWithNewToken
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@interface FBAXTranslationRequest_FrontmostApplication : FBAXTranslationRequest

@end

@implementation FBAXTranslationRequest_FrontmostApplication

- (AXPTranslationObject *)performWithTranslator:(AXPTranslator *)translator
{
  return [translator frontmostApplicationWithDisplayId:0 bridgeDelegateToken:self.token];
}

- (nullable id)serialize:(AXPMacPlatformElement *)element error:(NSError **)error
{
  return [FBSimulatorAccessibilitySerializer recursiveDescriptionFromElement:element token:self.token nestedFormat:self.nestedFormat keys:self.keys collector:self.collector maxDepth:self.maxDepth];
}

- (instancetype)cloneWithNewToken
{
  return [[FBAXTranslationRequest_FrontmostApplication alloc] initWithNestedFormat:self.nestedFormat keys:self.keys maxDepth:self.maxDepth];
}

@end

@interface FBAXTranslationAction : NSObject

@property (nonatomic, assign, readonly) BOOL performTap;
@property (nonatomic, assign, readonly) CGPoint point;
@property (nonatomic, copy, nullable, readonly) NSString *expectedLabel;

@end

@implementation FBAXTranslationAction

- (instancetype)initWithPerformTap:(BOOL)performTap expectedLabel:(nullable NSString *)expectedLabel point:(CGPoint)point;
{
  self = [super init];
  if (!self) {
    return nil;
  }
  
  _performTap = performTap;
  _point = point;
  _expectedLabel = expectedLabel;

  return self;
}

- (BOOL)performActionOnElement:(AXPMacPlatformElement *)element error:(NSError **)error
{
  NSString *expectedLabel = self.expectedLabel;
  if (expectedLabel) {
    NSString *actualLabel = element.accessibilityLabel;
    if (![expectedLabel isEqualToString:actualLabel]) {
      return [[FBSimulatorError
        describeFormat:@"The element at point %@ does not have the expected label %@. Actual label %@", NSStringFromPoint(self.point), expectedLabel, actualLabel]
        failBool:error];
    }
  }
  if (self.performTap) {
    NSArray<NSString *> *actionNames = element.accessibilityActionNames;
    if ([actionNames containsObject:@"AXPress"] == NO) {
      return [[FBSimulatorError
        describeFormat:@"The element at point %@ with label %@ does not support pressing. Supported actions %@", NSStringFromPoint(self.point), element.accessibilityIdentifier, [FBCollectionInformation oneLineDescriptionFromArray:actionNames]]
        failBool:error];
    }
    if ([element accessibilityPerformPress] == NO) {
      return [[FBSimulatorError
        describeFormat:@"Performing accessibilityPerformPress on element at point %@ with label %@ did not succeed", NSStringFromPoint(self.point), element.accessibilityIdentifier]
        failBool:error];
    }
  }
  return YES;
}

@end

@interface FBAXTranslationRequest_Point : FBAXTranslationRequest

@property (nonatomic, assign, readonly) CGPoint point;
@property (nonatomic, strong, nullable, readonly) FBAXTranslationAction *action;

@end

@implementation FBAXTranslationRequest_Point

- (instancetype)initWithNestedFormat:(BOOL)nestedFormat point:(CGPoint)point action:(FBAXTranslationAction *)action keys:(NSSet<NSString *> *)keys maxDepth:(NSUInteger)maxDepth
{
  self = [super initWithNestedFormat:nestedFormat keys:keys maxDepth:maxDepth];
  if (!self) {
    return nil;
  }

  _point = point;
  _action = action;

  return self;
}

- (AXPTranslationObject *)performWithTranslator:(AXPTranslator *)translator
{
  return [translator objectAtPoint:self.point displayId:0 bridgeDelegateToken:self.token];
}

- (NSDictionary<NSString *, id> *)serialize:(AXPMacPlatformElement *)element error:(NSError **)error
{
  NSDictionary<NSString *, id> *result = [FBSimulatorAccessibilitySerializer formattedDescriptionOfElement:element token:self.token nestedFormat:self.nestedFormat keys:self.keys collector:self.collector maxDepth:self.maxDepth];
  FBAXTranslationAction *action = self.action;
  if (action && [action performActionOnElement:element error:error] == NO) {
    return nil;
  }
  return result;
}

- (instancetype)cloneWithNewToken
{
  return [[FBAXTranslationRequest_Point alloc] initWithNestedFormat:self.nestedFormat point:self.point action:self.action keys:self.keys maxDepth:self.maxDepth];
}

@end


@interface FBAXTranslationDispatcher : NSObject <AXPTranslationTokenDelegateHelper>

@property (nonatomic, weak, readonly) AXPTranslator *translator;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;
@property (nonatomic, strong, readonly) dispatch_queue_t xpcCompletionQueue;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, FBAXTranslationRequest *> *tokenToRequest;

@end

@implementation FBAXTranslationDispatcher

static void *FBAXTranslationDispatcherWorkQueueKey = &FBAXTranslationDispatcherWorkQueueKey;

#pragma mark Initializers

- (instancetype)initWithTranslator:(AXPTranslator *)translator logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _translator = translator;
  _logger = logger;
  _workQueue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.accessibility_translator.work", DISPATCH_QUEUE_SERIAL);
  dispatch_queue_set_specific(_workQueue, FBAXTranslationDispatcherWorkQueueKey, FBAXTranslationDispatcherWorkQueueKey, NULL);
  // Use a separate queue for CoreSimulator callbacks. Never use the same serial queue that is doing the synchronous wait.
  _xpcCompletionQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
  _tokenToRequest = [NSMutableDictionary dictionary];

  return self;
}

#pragma mark Public

- (FBFutureContext<NSArray<id> *> *)translationObjectAndMacPlatformElementForSimulator:(FBSimulator *)simulator request:(FBAXTranslationRequest *)request
{
  return [[FBFuture
    onQueue:self.workQueue resolveValue:^ NSArray<id> * (NSError **error){
      request.device = simulator.device;
      [self pushRequest:request];
      FBAccessibilityProfilingCollector *collector = request.collector;

      // Record translation timing
      CFAbsoluteTime translationStart = CFAbsoluteTimeGetCurrent();
      AXPTranslationObject *translation = [request performWithTranslator:self.translator];
      if (collector) {
        collector.translationDuration = CFAbsoluteTimeGetCurrent() - translationStart;
      }

      if (translation == nil) {
        return [[FBSimulatorError
          describeFormat:@"No translation object returned for simulator. This means you have likely specified a point onscreen that is invalid or invisible due to a fullscreen dialog"]
          fail:error];
      }
      translation.bridgeDelegateToken = request.token;

      // Record element conversion timing
      CFAbsoluteTime conversionStart = CFAbsoluteTimeGetCurrent();
      AXPMacPlatformElement *element = [self.translator macPlatformElementFromTranslation:translation];
      if (collector) {
        collector.elementConversionDuration = CFAbsoluteTimeGetCurrent() - conversionStart;
      }

      element.translation.bridgeDelegateToken = request.token;
      return @[translation, element];
    }]
    onQueue:self.workQueue contextualTeardown:^ FBFuture<NSNull *> * (id _, FBFutureState __){
      [self popRequest:request];
      return FBFuture.empty;
    }];
}

#pragma mark Private

- (void)pushRequest:(FBAXTranslationRequest *)request
{
  NSParameterAssert([self.tokenToRequest objectForKey:request.token] == nil);
  [self.tokenToRequest setObject:request forKey:request.token];
  [self.logger logFormat:@"Registered request with token %@", request.token];
}

- (void)popRequest:(FBAXTranslationRequest *)request
{
  NSParameterAssert([self.tokenToRequest objectForKey:request.token] != nil);
  [self.tokenToRequest removeObjectForKey:request.token];
  [self.logger logFormat:@"Removed request with token %@", request.token];
}

#pragma mark AXPTranslationTokenDelegateHelper

// Since we're using an async callback-based function in CoreSimulator this needs to be converted to a synchronous variant for the AXTranslator callbacks.
// In order to do this we have a dispatch group acting as a mutex.
// This also means that the queue that this happens on should **never be the main queue**. An async global queue will suffice here.
- (AXPTranslationCallback)accessibilityTranslationDelegateBridgeCallbackWithToken:(NSString *)token
{
  __block FBAXTranslationRequest *request = nil;
  if (dispatch_get_specific(FBAXTranslationDispatcherWorkQueueKey)) {
    request = [self.tokenToRequest objectForKey:token];
  } else {
    dispatch_sync(self.workQueue, ^{
      request = [self.tokenToRequest objectForKey:token];
    });
  }
  if (!request) {
    return ^ AXPTranslatorResponse * (AXPTranslatorRequest *axRequest) {
      [self.logger logFormat:@"Request with token %@ is gone. Returning empty response", token];
      return [objc_getClass("AXPTranslatorResponse") emptyResponse];
    };
  }
  SimDevice *device = request.device;
  FBAccessibilityProfilingCollector *collector = request.collector;
  id<FBControlCoreLogger> logger = request.logger;
  return ^ AXPTranslatorResponse * (AXPTranslatorRequest *axRequest){
    if (logger) {
      [logger logFormat:@"Sending Accessibility Request %@", axRequest];
    }
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    __block AXPTranslatorResponse *response = nil;

    CFAbsoluteTime xpcStart = CFAbsoluteTimeGetCurrent();
    [device sendAccessibilityRequestAsync:axRequest completionQueue:self.xpcCompletionQueue completionHandler:^(AXPTranslatorResponse *innerResponse) {
      response = innerResponse;
      dispatch_group_leave(group);
    }];
    // CoreSimulator accessibility requests should never block forever.
    // If this times out, return an empty response so the overall request can complete (with partial data) or fail upstream.
    dispatch_time_t timeout = FBCreateDispatchTimeFromDuration(FBControlCoreGlobalConfiguration.regularTimeout);
    long waitResult = dispatch_group_wait(group, timeout);
    if (waitResult != 0) {
      if (logger) {
        [logger logFormat:@"Timed out waiting for CoreSimulator accessibility response (token=%@ request=%@)", token, axRequest];
      }
      return [objc_getClass("AXPTranslatorResponse") emptyResponse];
    }
    if (collector) {
      [collector addXPCCallDuration:CFAbsoluteTimeGetCurrent() - xpcStart];
    }

    if (logger) {
      [logger logFormat:@"Got Accessibility Response %@", response];
    }
    return response;
  };
}

- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withToken:(NSString *)token
{
  return rect;
}

- (id)accessibilityTranslationRootParentWithToken:(NSString *)token
{
  [self.logger logFormat:@"Delegate method '%@', with unknown implementation called with token %@. Returning nil.", NSStringFromSelector(_cmd), token];
  return nil;
}

@end

#pragma mark - FBSimulator Instance Method for Translation Dispatcher

@implementation FBSimulator (FBAccessibilityDispatcher)

+ (id)createAccessibilityTranslationDispatcherWithTranslator:(id)translator
{
  FBAXTranslationDispatcher *dispatcher =
    [[FBAXTranslationDispatcher alloc] initWithTranslator:translator logger:nil];
  ((AXPTranslator *)translator).bridgeTokenDelegate = dispatcher;
  return dispatcher;
}

- (id)accessibilityTranslationDispatcher
{
  static dispatch_once_t onceToken;
  static FBAXTranslationDispatcher *dispatcher;
  dispatch_once(&onceToken, ^{
    AXPTranslator *translator = [objc_getClass("AXPTranslator") sharedInstance];
    dispatcher = [FBSimulator createAccessibilityTranslationDispatcherWithTranslator:translator];
  });
  return dispatcher;
}

@end

@interface FBSimulatorAccessibilityCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

+ (nullable AXUIElementRef)copyFirstDescendantMatchingDeviceWindowFromElement:(AXUIElementRef)element deviceName:(nullable NSString *)deviceName depthRemaining:(NSUInteger)depthRemaining;
+ (nullable AXUIElementRef)copySimDisplayRenderableViewFromSystemWideForDeviceName:(nullable NSString *)deviceName simulatorPID:(pid_t)simulatorPID windowTitles:(NSArray<NSString *> **)windowTitles;

@end

static NSString *const CoreSimulatorBridgeServiceName = @"com.apple.CoreSimulator.bridge";

@implementation FBSimulatorAccessibilityCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)targets
{
  return [[self alloc] initWithSimulator:targets];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark FBSimulatorAccessibilityCommands Protocol Implementation

- (FBFuture<FBAccessibilityElementsResponse *> *)accessibilityElementsWithOptions:(FBAccessibilityRequestOptions *)options
{
  FBSimulator *simulator = self.simulator;
  NSError *error = nil;
  if (![self validateAccessibilityWithError:&error]) {
    return [FBFuture futureWithError:error];
  }

  FBAXTranslationRequest *translationRequest = [[FBAXTranslationRequest_FrontmostApplication alloc] initWithNestedFormat:options.nestedFormat keys:options.keys maxDepth:options.maxDepth];
  if (options.enableProfiling) {
    translationRequest.collector = [[FBAccessibilityProfilingCollector alloc] init];
  }
  if (options.enableLogging) {
    translationRequest.logger = simulator.logger;
  }
  return [FBSimulatorAccessibilityCommands accessibilityElementWithTranslationRequest:translationRequest simulator:simulator remediationPermitted:YES];
}

- (FBFuture<FBAccessibilityElementsResponse *> *)accessibilityElementAtPoint:(CGPoint)point options:(FBAccessibilityRequestOptions *)options
{
  FBSimulator *simulator = self.simulator;
  NSError *error = nil;
  if (![self validateAccessibilityWithError:&error]) {
    return [FBFuture futureWithError:error];
  }

  FBAXTranslationRequest *translationRequest = [[FBAXTranslationRequest_Point alloc] initWithNestedFormat:options.nestedFormat point:point action:nil keys:options.keys maxDepth:options.maxDepth];
  if (options.enableProfiling) {
    translationRequest.collector = [[FBAccessibilityProfilingCollector alloc] init];
  }
  if (options.enableLogging) {
    translationRequest.logger = simulator.logger;
  }
  return [FBSimulatorAccessibilityCommands accessibilityElementWithTranslationRequest:translationRequest simulator:simulator remediationPermitted:NO];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityPerformTapOnElementAtPoint:(CGPoint)point expectedLabel:(NSString *)expectedLabel
{
  FBSimulator *simulator = self.simulator;
  NSError *error = nil;
  if (![self validateAccessibilityWithError:&error]) {
    return [FBFuture futureWithError:error];
  }

  FBAXTranslationAction *action = [[FBAXTranslationAction alloc] initWithPerformTap:YES expectedLabel:expectedLabel point:point];
  FBAXTranslationRequest *translationRequest = [[FBAXTranslationRequest_Point alloc] initWithNestedFormat:YES point:point action:action keys:FBAXKeysDefaultSet() maxDepth:0];
  // Extract .elements from the response since this method returns raw dictionary
  return [[FBSimulatorAccessibilityCommands accessibilityElementWithTranslationRequest:translationRequest simulator:simulator remediationPermitted:NO]
    onQueue:simulator.workQueue map:^NSDictionary *(FBAccessibilityElementsResponse *response) {
      return response.elements;
    }];
}

#pragma mark Private

// Uses the CoreSimulator accessibility API via -[SimDevice sendAccessibilityRequestAsync:completionQueue:completionHandler:]
// This API requires Xcode 12+ to have been installed on the host at some point.
- (BOOL)validateAccessibilityWithError:(NSError **)error
{
  FBSimulator *simulator = self.simulator;
  if (simulator.state != FBiOSTargetStateBooted) {
    return [[FBControlCoreError
      describeFormat:@"Cannot run accessibility commands against %@ as it is not booted", simulator]
      failBool:error];
  }
  SimDevice *device = simulator.device;
  if (![device respondsToSelector:@selector(sendAccessibilityRequestAsync:completionQueue:completionHandler:)]) {
    return [[FBControlCoreError
      describeFormat:@"-[SimDevice %@] is not present on this host, you must install and/or use Xcode 12 to use accessibility.", NSStringFromSelector(@selector(sendAccessibilityRequestAsync:completionQueue:completionHandler:))]
      failBool:error];
  }
  if (![FBSimulatorControlFrameworkLoader.accessibilityFrameworks loadPrivateFrameworks:simulator.logger error:error]) {
    return NO;
  }
  return YES;
}

+ (FBFuture<FBAccessibilityElementsResponse *> *)accessibilityElementWithTranslationRequest:(FBAXTranslationRequest *)request simulator:(FBSimulator *)simulator remediationPermitted:(BOOL)remediationPermitted
{
  FBAXTranslationDispatcher *dispatcher = (FBAXTranslationDispatcher *) simulator.accessibilityTranslationDispatcher;
  dispatch_queue_t serializationQueue = dispatcher.workQueue ?: simulator.asyncQueue;
  return [[[[simulator.accessibilityTranslationDispatcher
    translationObjectAndMacPlatformElementForSimulator:simulator request:request]
    // This next steps appends remediation information (if required).
    // The remediation detection has a short circuit so that the common case (no remediation required) is fast.
    onQueue:simulator.asyncQueue pend:^ FBFuture<NSArray<id> *> * (NSArray<id> *tuple){
      AXPTranslationObject *translationObject = tuple[0];
      AXPMacPlatformElement *macPlatformElement = tuple[1];
      // Only see if remediation is needed if requested. This also ensures that the attempt *after* remediation will not infinitely recurse.
      if (remediationPermitted) {
        return [[FBSimulatorAccessibilityCommands
          remediationRequiredForSimulator:simulator
          translationObject:translationObject
          macPlatformElement:macPlatformElement]
          onQueue:simulator.asyncQueue map:^ NSArray<id> * (NSNumber *remediationRequired) {
            return @[translationObject, macPlatformElement, remediationRequired];
          }];
      }
      return [FBFuture futureWithResult:@[translationObject, macPlatformElement, @NO]];
    }]
    onQueue:serializationQueue pop:^ id (NSArray<id> *tuple){
      // If remediation is required, then return an empty value, we pop the context here to finish the translation process.
      BOOL remediationRequired = [tuple[2] boolValue];
      if (remediationRequired) {
        return FBFuture.empty;
      }
      // Otherwise serialize now, when the context has popped the token is then deregistered.
      AXPMacPlatformElement *element = tuple[1];
      FBAccessibilityProfilingCollector *collector = request.collector;

      // Track serialization timing if profiling
      CFAbsoluteTime serializationStart = CFAbsoluteTimeGetCurrent();
      NSError *error = nil;
      id serialized = [request serialize:element error:&error];
      if (serialized == nil) {
        return [FBFuture futureWithError:error];
      }
      CFAbsoluteTime serializationDuration = CFAbsoluteTimeGetCurrent() - serializationStart;

      // Always wrap result in FBAccessibilityElementsResponse
      // profilingData is nil when profile=NO
      FBAccessibilityProfilingData *profilingData = nil;
      if (collector) {
        profilingData = [collector finalizeWithSerializationDuration:serializationDuration];
      }
      FBAccessibilityElementsResponse *response = [[FBAccessibilityElementsResponse alloc]
        initWithElements:serialized
           profilingData:profilingData];
      return [FBFuture futureWithResult:response];
    }]
    onQueue:serializationQueue fmap:^ FBFuture<FBAccessibilityElementsResponse *> * (FBAccessibilityElementsResponse *result) {
      // At this point we will either have an empty result, or the result.
      // In the empty (remediation) state, then we should recurse, but not allow further remediation.
      if ([result isEqual:NSNull.null]) {
        FBAXTranslationRequest *nextRequest = [request cloneWithNewToken];
        return [[self
          remediateSpringBoardForSimulator:simulator]
          onQueue:serializationQueue fmap:^ FBFuture<FBAccessibilityElementsResponse *> * (id _) {
            return [self accessibilityElementWithTranslationRequest:nextRequest simulator:simulator remediationPermitted:NO];
          }];
      }
      return [FBFuture futureWithResult:result];
    }];
}

+ (FBFuture<NSNumber *> *)remediationRequiredForSimulator:(FBSimulator *)simulator translationObject:(AXPTranslationObject *)translationObject macPlatformElement:(AXPMacPlatformElement *)macPlatformElement
{
  // First perform a quick check, if the accessibility frame is zero, then this is indicative of the problem
  if (CGRectEqualToRect(macPlatformElement.accessibilityFrame, CGRectZero) == NO) {
    return [FBFuture futureWithResult:@NO];
  }
  // Then confirm whether the pid of the translation object represents a real pid within the simulator.
  // If it does not, then it likely means that we got the pid of the crashed SpringBoard.
  // A crashed SpringBoard, means that there is a new one running (or else the Simulator is completely hosed).
  // In this case, the remediation is to restart CoreSimulatorBridge, since the CoreSimulatorBridge needs restarting upon a crash.
  // In all likelihood CoreSimulatorBridge contains a constant reference to the pid of SpringBoard and the most effective way of resolving this is to stop it.
  // The Simulator's launchctl will then make sure that the SimulatorBridge is restarted (just like it does for SpringBoard itself).
  pid_t processIdentifier = translationObject.pid;
  return [[[simulator
    serviceNameForProcessIdentifier:processIdentifier]
    mapReplace:@NO]
    onQueue:simulator.workQueue handleError:^(NSError *error) {
      [simulator.logger logFormat:@"pid %d does not exist, this likely means that SpringBoard has restarted, %@ should be restarted", processIdentifier, CoreSimulatorBridgeServiceName];
      return [FBFuture futureWithResult:@YES];
    }];
}

+ (FBFuture<NSNull *> *)remediateSpringBoardForSimulator:(FBSimulator *)simulator
{
  return [[[simulator
    stopServiceWithName:CoreSimulatorBridgeServiceName]
    mapReplace:NSNull.null]
    rephraseFailure:@"Could not restart %@ bridge when attempting to remediate SpringBoard Crash", CoreSimulatorBridgeServiceName];
}

#pragma mark - AXUIElement-based Accessibility (macOS System API)

- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibilityElementsViaAXUIElementForSimulatorPID:(pid_t)simulatorPID deviceName:(nullable NSString *)deviceName nestedFormat:(BOOL)nestedFormat
{
  return [FBFuture onQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0) resolveValue:^NSArray<NSDictionary<NSString *, id> *> *(NSError **error) {
    if (!AXIsProcessTrusted()) {
      [[FBSimulatorError
        describeFormat:@"AXUIElement accessibility query requires Accessibility permission for bundle %@ (AXIsProcessTrusted() returned NO)",
        NSBundle.mainBundle.bundlePath]
        fail:error];
      return nil;
    }

    __block NSArray<NSDictionary<NSString *, id> *> *result = nil;
    __block NSError *innerError = nil;

    dispatch_sync(dispatch_get_main_queue(), ^{
      NSRunningApplication *simulatorApp = [NSRunningApplication runningApplicationWithProcessIdentifier:simulatorPID];
      [simulatorApp activateWithOptions:NSApplicationActivateAllWindows];
      [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];

      AXUIElementRef appRef = AXUIElementCreateApplication(simulatorPID);
      if (!appRef) {
        [[FBSimulatorError describeFormat:@"Failed to create AXUIElement for Simulator PID %d", simulatorPID] fail:&innerError];
        return;
      }

      AXError windowsError = kAXErrorSuccess;
      NSArray<NSString *> *windowTitles = nil;
      AXUIElementRef renderableView = [FBSimulatorAccessibilityCommands copySimDisplayRenderableViewFromSystemWideForDeviceName:deviceName simulatorPID:simulatorPID windowTitles:&windowTitles];
      if (!renderableView) {
        renderableView = [FBSimulatorAccessibilityCommands copySimDisplayRenderableViewFromApp:appRef deviceName:deviceName windowsError:&windowsError windowTitles:&windowTitles];
      }
      CFRelease(appRef);
      if (!renderableView) {
        [[FBSimulatorError
          describeFormat:@"Could not find SimDisplayRenderableView in Simulator.app (PID %d, device: %@, AX windows error: %@, AX window titles: %@, CG window titles: %@, bundle: %@)",
          simulatorPID,
          deviceName ?: @"any",
          FBAXErrorDescription(windowsError),
          windowTitles ?: @[],
          FBCGWindowTitlesForPID(simulatorPID),
          NSBundle.mainBundle.bundlePath]
          fail:&innerError];
        return;
      }

      CGPoint renderableOrigin = [FBSimulatorAccessibilityCommands originOfElement:renderableView];
      if (nestedFormat) {
        NSDictionary *tree = [FBSimulatorAccessibilityCommands nestedDictionaryFromAXElement:renderableView origin:renderableOrigin];
        result = tree ? @[tree] : @[];
      } else {
        result = [FBSimulatorAccessibilityCommands flatArrayFromAXElement:renderableView origin:renderableOrigin];
      }
      CFRelease(renderableView);
    });

    if (!result) {
      if (innerError) {
        if (error) {
          *error = innerError;
        }
        return nil;
      }
      [[FBSimulatorError describe:@"AXUIElement accessibility query returned no result"] fail:error];
      return nil;
    }
    return result;
  }];
}

+ (nullable AXUIElementRef)copySimDisplayRenderableViewFromApp:(AXUIElementRef)appRef deviceName:(nullable NSString *)deviceName windowsError:(AXError *)windowsError windowTitles:(NSArray<NSString *> **)windowTitles
{
  NSMutableArray<NSString *> *titles = [NSMutableArray array];

  // First try the focused/main window paths. These often work even when kAXWindowsAttribute
  // intermittently returns kAXErrorCannotComplete for Simulator.app.
  for (NSString *attributeName in @[(__bridge NSString *)kAXFocusedWindowAttribute, (__bridge NSString *)kAXMainWindowAttribute]) {
    CFTypeRef windowRef = NULL;
    AXError err = AXUIElementCopyAttributeValue(appRef, (__bridge CFStringRef)attributeName, &windowRef);
    if (err == kAXErrorSuccess && windowRef && CFGetTypeID(windowRef) == AXUIElementGetTypeID()) {
      AXUIElementRef window = (AXUIElementRef)windowRef;
      NSString *title = FBAXStringAttributeValue(window, kAXTitleAttribute);
      if (title.length > 0) {
        [titles addObject:title];
      }
      if (FBAXTitleMatchesDeviceName(window, deviceName)) {
        AXUIElementRef renderableView = [self copyRenderableViewFromElement:window];
        CFRelease(windowRef);
        if (renderableView) {
          if (windowsError) {
            *windowsError = kAXErrorSuccess;
          }
          if (windowTitles) {
            *windowTitles = [titles copy];
          }
          return renderableView;
        }
      } else {
        CFRelease(windowRef);
      }
    }
  }

  // Retry kAXWindowsAttribute a few times. Simulator.app sometimes reports kAXErrorCannotComplete
  // briefly even though the window tree becomes queryable moments later.
  AXError lastWindowsError = kAXErrorSuccess;
  for (NSUInteger attempt = 0; attempt < 5; attempt++) {
    CFArrayRef windowsRef = NULL;
    AXError err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute, (CFTypeRef *)&windowsRef);
    lastWindowsError = err;
    if (err == kAXErrorSuccess && windowsRef) {
      CFIndex windowCount = CFArrayGetCount(windowsRef);
      for (CFIndex i = 0; i < windowCount; i++) {
        AXUIElementRef window = (AXUIElementRef)CFArrayGetValueAtIndex(windowsRef, i);
        NSString *title = FBAXStringAttributeValue(window, kAXTitleAttribute);
        if (title.length > 0) {
          [titles addObject:title];
        }
        if (!FBAXTitleMatchesDeviceName(window, deviceName)) {
          continue;
        }
        AXUIElementRef renderableView = [self copyRenderableViewFromElement:window];
        if (renderableView) {
          CFRelease(windowsRef);
          if (windowsError) {
            *windowsError = kAXErrorSuccess;
          }
          if (windowTitles) {
            *windowTitles = [titles copy];
          }
          return renderableView;
        }
      }
      CFRelease(windowsRef);
      break;
    }
    usleep((useconds_t)(100000 * (attempt + 1)));
  }

  // Final fallback: walk the app's direct AX descendants and look for a descendant whose
  // title/description matches the device window. This avoids relying on kAXWindowsAttribute.
  AXUIElementRef renderableView = [self copyFirstDescendantMatchingDeviceWindowFromElement:appRef deviceName:deviceName depthRemaining:4];
  if (renderableView) {
    if (windowsError) {
      *windowsError = kAXErrorSuccess;
    }
    if (windowTitles) {
      *windowTitles = [titles copy];
    }
    return renderableView;
  }

  if (windowsError) {
    *windowsError = lastWindowsError;
  }
  if (windowTitles) {
    *windowTitles = [titles copy];
  }
  return NULL;
}

+ (nullable AXUIElementRef)copySimDisplayRenderableViewFromSystemWideForDeviceName:(nullable NSString *)deviceName simulatorPID:(pid_t)simulatorPID windowTitles:(NSArray<NSString *> **)windowTitles
{
  AXUIElementRef systemWide = AXUIElementCreateSystemWide();
  if (!systemWide) {
    if (windowTitles) {
      *windowTitles = @[];
    }
    return NULL;
  }

  NSMutableArray<NSString *> *titles = [NSMutableArray array];
  AXUIElementRef focusedApp = NULL;
  AXError focusedAppError = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute, (CFTypeRef *)&focusedApp);
  CFRelease(systemWide);
  if (focusedAppError != kAXErrorSuccess || focusedApp == NULL) {
    if (windowTitles) {
      *windowTitles = [titles copy];
    }
    return NULL;
  }

  pid_t focusedPID = 0;
  AXUIElementGetPid(focusedApp, &focusedPID);
  if (focusedPID != simulatorPID) {
    CFRelease(focusedApp);
    if (windowTitles) {
      *windowTitles = [titles copy];
    }
    return NULL;
  }

  for (NSString *attributeName in @[(__bridge NSString *)kAXFocusedWindowAttribute, (__bridge NSString *)kAXMainWindowAttribute]) {
    CFTypeRef windowRef = NULL;
    AXError err = AXUIElementCopyAttributeValue(focusedApp, (__bridge CFStringRef)attributeName, &windowRef);
    if (err != kAXErrorSuccess || windowRef == NULL || CFGetTypeID(windowRef) != AXUIElementGetTypeID()) {
      continue;
    }
    AXUIElementRef window = (AXUIElementRef)windowRef;
    NSString *title = FBAXStringAttributeValue(window, kAXTitleAttribute);
    if (title.length > 0) {
      [titles addObject:title];
    }
    if (FBAXTitleMatchesDeviceName(window, deviceName)) {
      AXUIElementRef renderableView = [self copyRenderableViewFromElement:window];
      CFRelease(windowRef);
      CFRelease(focusedApp);
      if (windowTitles) {
        *windowTitles = [titles copy];
      }
      return renderableView;
    }
    CFRelease(windowRef);
  }

  AXUIElementRef renderableView = [self copyFirstDescendantMatchingDeviceWindowFromElement:focusedApp deviceName:deviceName depthRemaining:4];
  CFRelease(focusedApp);
  if (windowTitles) {
    *windowTitles = [titles copy];
  }
  return renderableView;
}

+ (nullable AXUIElementRef)copyFirstDescendantMatchingDeviceWindowFromElement:(AXUIElementRef)element deviceName:(nullable NSString *)deviceName depthRemaining:(NSUInteger)depthRemaining
{
  if (FBAXTitleMatchesDeviceName(element, deviceName)) {
    AXUIElementRef renderableView = [self copyRenderableViewFromElement:element];
    if (renderableView) {
      return renderableView;
    }
  }
  if (depthRemaining == 0) {
    return NULL;
  }
  for (id childObj in [self mergedChildrenOfAXElement:element]) {
    AXUIElementRef child = (__bridge AXUIElementRef)childObj;
    AXUIElementRef renderableView = [self copyFirstDescendantMatchingDeviceWindowFromElement:child deviceName:deviceName depthRemaining:depthRemaining - 1];
    if (renderableView) {
      return renderableView;
    }
  }
  return NULL;
}

+ (nullable AXUIElementRef)copyRenderableViewFromElement:(AXUIElementRef)element
{
  // Use the merged child enumeration here too: in iOS 26 the SimDisplayRenderableView
  // itself may surface its iOS subtree via AXChildrenInNavigationOrder rather than
  // kAXChildrenAttribute, which would otherwise cause us to skip the renderable view
  // entirely and fall back to the lossy XPC path.
  NSArray *children = [self mergedChildrenOfAXElement:element];
  AXUIElementRef result = NULL;

  for (id childObj in children) {
    AXUIElementRef child = (__bridge AXUIElementRef)childObj;

    CFTypeRef roleRef = NULL;
    AXUIElementCopyAttributeValue(child, kAXRoleAttribute, &roleRef);
    if (!roleRef) continue;

    NSString *role = (__bridge NSString *)roleRef;
    BOOL isGroup = [role isEqualToString:NSAccessibilityGroupRole];
    CFRelease(roleRef);

    if (isGroup) {
      CFTypeRef descRef = NULL;
      AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute, &descRef);
      NSString *desc = descRef ? (__bridge_transfer NSString *)descRef : nil;

      // SimDisplayRenderableView typically has no description or a specific one.
      // It's the first group directly under the window that contains the iOS content.
      // We verify by checking it exposes children via any standard child attribute.
      if ([self mergedChildrenOfAXElement:child].count > 0) {
        result = child;
        CFRetain(result);
        break;
      }
      (void)desc;
    }
  }

  return result;
}

+ (CGPoint)originOfElement:(AXUIElementRef)element
{
  CFTypeRef posRef = NULL;
  AXError err = AXUIElementCopyAttributeValue(element, kAXPositionAttribute, &posRef);
  if (err != kAXErrorSuccess || !posRef) {
    return CGPointZero;
  }
  CGPoint point = CGPointZero;
  AXValueGetValue(posRef, kAXValueCGPointType, &point);
  CFRelease(posRef);
  return point;
}

+ (CGSize)sizeOfElement:(AXUIElementRef)element
{
  CFTypeRef sizeRef = NULL;
  AXError err = AXUIElementCopyAttributeValue(element, kAXSizeAttribute, &sizeRef);
  if (err != kAXErrorSuccess || !sizeRef) {
    return CGSizeZero;
  }
  CGSize size = CGSizeZero;
  AXValueGetValue(sizeRef, kAXValueCGSizeType, &size);
  CFRelease(sizeRef);
  return size;
}

static NSString *FBStringAttributeFromAXElement(AXUIElementRef element, CFStringRef attribute)
{
  CFTypeRef ref = NULL;
  AXError err = AXUIElementCopyAttributeValue(element, attribute, &ref);
  if (err != kAXErrorSuccess || !ref) return nil;
  if (CFGetTypeID(ref) != CFStringGetTypeID()) {
    CFRelease(ref);
    return nil;
  }
  return (__bridge_transfer NSString *)ref;
}

static NSNumber *FBBoolAttributeFromAXElement(AXUIElementRef element, CFStringRef attribute)
{
  CFTypeRef ref = NULL;
  AXError err = AXUIElementCopyAttributeValue(element, attribute, &ref);
  if (err != kAXErrorSuccess || !ref) return nil;
  if (CFGetTypeID(ref) != CFBooleanGetTypeID()) {
    CFRelease(ref);
    return nil;
  }
  BOOL value = (BOOL)CFBooleanGetValue(ref);
  CFRelease(ref);
  return @(value);
}

+ (NSDictionary<NSString *, id> *)dictionaryFromAXElement:(AXUIElementRef)element origin:(CGPoint)containerOrigin
{
  NSMutableDictionary<NSString *, id> *dict = [NSMutableDictionary dictionary];

  // Position & size -> frame in simulator-relative coordinates
  CGPoint pos = [self originOfElement:element];
  CGSize size = [self sizeOfElement:element];
  CGRect frame = CGRectMake(pos.x - containerOrigin.x, pos.y - containerOrigin.y, size.width, size.height);

  dict[FBAXKeysFrame] = NSStringFromRect(frame);
  dict[FBAXKeysFrameDict] = @{
    @"x": @(frame.origin.x),
    @"y": @(frame.origin.y),
    @"width": @(frame.size.width),
    @"height": @(frame.size.height),
  };

  NSString *role = FBStringAttributeFromAXElement(element, kAXRoleAttribute);
  dict[FBAXKeysRole] = role ?: [NSNull null];

  NSString *typeValue = role;
  if ([role hasPrefix:@"AX"]) {
    typeValue = [role substringFromIndex:2];
  }
  dict[FBAXKeysType] = typeValue ?: [NSNull null];

  NSString *label = FBStringAttributeFromAXElement(element, kAXDescriptionAttribute);
  dict[FBAXKeysLabel] = label ?: [NSNull null];

  NSString *value = FBStringAttributeFromAXElement(element, kAXValueAttribute);
  dict[FBAXKeysValue] = value ?: [NSNull null];

  NSString *identifier = FBStringAttributeFromAXElement(element, CFSTR("AXIdentifier"));
  dict[FBAXKeysUniqueID] = identifier ?: [NSNull null];

  NSString *title = FBStringAttributeFromAXElement(element, kAXTitleAttribute);
  dict[FBAXKeysTitle] = title ?: [NSNull null];

  NSString *help = FBStringAttributeFromAXElement(element, kAXHelpAttribute);
  dict[FBAXKeysHelp] = help ?: [NSNull null];

  NSNumber *enabled = FBBoolAttributeFromAXElement(element, CFSTR("AXEnabled"));
  dict[FBAXKeysEnabled] = enabled ?: @YES;

  NSString *roleDescription = FBStringAttributeFromAXElement(element, kAXRoleDescriptionAttribute);
  dict[FBAXKeysRoleDescription] = roleDescription ?: [NSNull null];

  NSString *subrole = FBStringAttributeFromAXElement(element, kAXSubroleAttribute);
  dict[FBAXKeysSubrole] = subrole ?: [NSNull null];

  dict[FBAXKeysContentRequired] = @NO;

  dict[FBAXKeysPID] = @0;

  // Custom actions
  CFArrayRef actionsRef = NULL;
  AXUIElementCopyActionNames(element, &actionsRef);
  NSArray *actions = actionsRef ? (__bridge_transfer NSArray *)actionsRef : @[];
  NSMutableArray *customActionNames = [NSMutableArray array];
  for (NSString *action in actions) {
    if (![action isEqualToString:@"AXPress"] && ![action isEqualToString:@"AXCancel"] &&
        ![action isEqualToString:@"AXRaise"] && ![action isEqualToString:@"AXShowMenu"]) {
      CFStringRef descRef = NULL;
      AXUIElementCopyActionDescription(element, (__bridge CFStringRef)action, &descRef);
      NSString *desc = descRef ? (__bridge_transfer NSString *)descRef : action;
      [customActionNames addObject:desc];
    }
  }
  dict[FBAXKeysCustomActions] = [customActionNames copy];

  // Simulator.app bridges iOS elements via AXPTranslator, so AXTraits may be
  // readable even through the C API. Fall back to NSNull when unavailable.
  CFTypeRef traitsRef = NULL;
  AXError traitsErr = AXUIElementCopyAttributeValue(element, CFSTR("AXTraits"), &traitsRef);
  if (traitsErr == kAXErrorSuccess && traitsRef && CFGetTypeID(traitsRef) == CFNumberGetTypeID()) {
    uint64_t bitmask = 0;
    CFNumberGetValue(traitsRef, kCFNumberLongLongType, &bitmask);
    dict[FBAXKeysTraits] = AXExtractTraits(bitmask).allObjects;
    CFRelease(traitsRef);
  } else {
    dict[FBAXKeysTraits] = [NSNull null];
    if (traitsRef) CFRelease(traitsRef);
  }

  return [dict copy];
}

// Some bridged iOS containers (notably the iOS 26 floating tab bar) return an empty
// kAXChildrenAttribute even though their children show up under attributes like
// AXChildrenInNavigationOrder, AXTabs, AXVisibleChildren, etc. Accessibility Inspector
// surfaces those tabs because it falls back across these alternate attributes.
// We mirror that behaviour by collecting children from every standard child-providing
// attribute and deduplicating by AXUIElementRef value (CFEqual-based) while preserving
// first-seen order, so kAXChildrenAttribute remains canonical when populated.
+ (NSArray *)mergedChildrenOfAXElement:(AXUIElementRef)element
{
  static CFStringRef const attrs[] = {
    kAXChildrenAttribute,
    CFSTR("AXChildrenInNavigationOrder"),
    kAXTabsAttribute,
    kAXVisibleChildrenAttribute,
    kAXSelectedChildrenAttribute,
    kAXContentsAttribute,
  };
  NSMutableArray *merged = [NSMutableArray array];
  CFMutableSetRef seen = CFSetCreateMutable(NULL, 0, &kCFTypeSetCallBacks);
  for (size_t i = 0; i < sizeof(attrs) / sizeof(attrs[0]); i++) {
    CFTypeRef value = NULL;
    AXError err = AXUIElementCopyAttributeValue(element, attrs[i], &value);
    if (err != kAXErrorSuccess || value == NULL) {
      continue;
    }
    if (CFGetTypeID(value) != CFArrayGetTypeID()) {
      CFRelease(value);
      continue;
    }
    CFArrayRef arr = (CFArrayRef)value;
    CFIndex count = CFArrayGetCount(arr);
    for (CFIndex j = 0; j < count; j++) {
      const void *item = CFArrayGetValueAtIndex(arr, j);
      if (item == NULL || CFGetTypeID(item) != AXUIElementGetTypeID()) {
        continue;
      }
      if (CFSetContainsValue(seen, item)) {
        continue;
      }
      CFSetAddValue(seen, item);
      [merged addObject:(__bridge id)item];
    }
    CFRelease(arr);
  }
  CFRelease(seen);
  return merged;
}

+ (NSArray<NSDictionary<NSString *, id> *> *)flatArrayFromAXElement:(AXUIElementRef)element origin:(CGPoint)containerOrigin
{
  NSMutableArray<NSDictionary<NSString *, id> *> *results = [NSMutableArray array];
  [self flatRecurseAXElement:element origin:containerOrigin into:results];
  return [results copy];
}

+ (void)flatRecurseAXElement:(AXUIElementRef)element origin:(CGPoint)containerOrigin into:(NSMutableArray<NSDictionary<NSString *, id> *> *)results
{
  [results addObject:[self dictionaryFromAXElement:element origin:containerOrigin]];

  for (id child in [self mergedChildrenOfAXElement:element]) {
    [self flatRecurseAXElement:(__bridge AXUIElementRef)child origin:containerOrigin into:results];
  }
}

+ (NSDictionary<NSString *, id> *)nestedDictionaryFromAXElement:(AXUIElementRef)element origin:(CGPoint)containerOrigin
{
  NSMutableDictionary<NSString *, id> *dict = [[self dictionaryFromAXElement:element origin:containerOrigin] mutableCopy];

  NSMutableArray<NSDictionary<NSString *, id> *> *childDicts = [NSMutableArray array];
  for (id child in [self mergedChildrenOfAXElement:element]) {
    NSDictionary *childDict = [self nestedDictionaryFromAXElement:(__bridge AXUIElementRef)child origin:containerOrigin];
    if (childDict) {
      [childDicts addObject:childDict];
    }
  }
  dict[@"children"] = childDicts;

  return [dict copy];
}

@end
