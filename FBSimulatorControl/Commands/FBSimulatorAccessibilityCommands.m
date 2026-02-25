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

#import "FBSimulator.h"
#import "FBSimulatorControlFrameworkLoader.h"
#import "FBSimulatorError.h"

#import <FBControlCore/FBAccessibilityTraits.h>

#import <stdatomic.h>

/**
 Mutable collector for profiling data during an accessibility request.
 This is a per-request object that accumulates timing and count data.
 Thread-safe via atomic operations for counters that may be incremented from callbacks.
 */
@interface FBAccessibilityProfilingCollector : NSObject

@property (nonatomic, assign) CFAbsoluteTime translationDuration;
@property (nonatomic, assign) CFAbsoluteTime elementConversionDuration;
@property (nonatomic, assign) CFAbsoluteTime serializationDuration;
@property (nonatomic, strong, readonly) NSSet<NSString *> *fetchedKeys;

- (void)incrementElementCount;
- (void)incrementAttributeFetchCountForKey:(nullable NSString *)key;
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
  NSMutableSet<NSString *> *_fetchedKeys;
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
  _fetchedKeys = [NSMutableSet set];
  return self;
}

- (void)incrementElementCount
{
  atomic_fetch_add(&_elementCount, 1);
}

- (void)incrementAttributeFetchCountForKey:(nullable NSString *)key
{
  atomic_fetch_add(&_attributeFetchCount, 1);
  if (key) {
    @synchronized(self) {
      [_fetchedKeys addObject:key];
    }
  }
}

- (NSSet<NSString *> *)fetchedKeys
{
  @synchronized(self) {
    return [_fetchedKeys copy];
  }
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
            totalXPCDuration:self.totalXPCDuration
                 fetchedKeys:self.fetchedKeys];
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

/**
 Category on FBAccessibilityElementsResponse providing a factory method
 that encapsulates timing calculation and profiling finalization.
 */
@implementation FBAccessibilityElementsResponse (ResponseBuilder)

+ (instancetype)responseWithElements:(id)elements
                  serializationStart:(CFAbsoluteTime)serializationStart
                           collector:(nullable FBAccessibilityProfilingCollector *)collector
                       frameCoverage:(nullable NSNumber *)frameCoverage
             additionalFrameCoverage:(nullable NSNumber *)additionalFrameCoverage
{
  CFAbsoluteTime serializationDuration = CFAbsoluteTimeGetCurrent() - serializationStart;

  FBAccessibilityProfilingData *profilingData = nil;
  if (collector) {
    profilingData = [collector finalizeWithSerializationDuration:serializationDuration];
  }

  return [[self alloc]
    initWithElements:elements
       profilingData:profilingData
       frameCoverage:frameCoverage
additionalFrameCoverage:additionalFrameCoverage];
}

@end

/**
 Grid-based coverage tracking for accessibility elements.
 Uses a coarse grid (default 10px cells) to track which areas of the screen
 are covered by accessibility elements. This handles overlapping elements correctly
 (a cell is either filled or not) and is computed incrementally during traversal.
 */
@interface FBAccessibilityCoverageGrid : NSObject

/// Initialize with screen bounds and optional cell size (default 10.0)
- (instancetype)initWithScreenBounds:(CGRect)bounds cellSize:(CGFloat)cellSize;
- (instancetype)initWithScreenBounds:(CGRect)bounds;

/// Mark cells covered by the given frame. Handles out-of-bounds frames safely.
- (void)markFilledWithFrame:(CGRect)frame;

/// Calculate coverage ratio for the entire screen.
/// Returns 0.0-1.0, or -1 if grid is invalid.
- (CGFloat)coverageRatio;

/// Check if the cell containing the given point is already filled.
/// Returns YES if the cell is marked, NO if empty or out of bounds.
- (BOOL)isFilledAtPoint:(CGPoint)point;

@property (nonatomic, readonly) CGRect screenBounds;
@property (nonatomic, readonly) CGFloat cellSize;
@property (nonatomic, readonly) NSUInteger width;
@property (nonatomic, readonly) NSUInteger height;

@end

@implementation FBAccessibilityCoverageGrid {
  uint8_t *_grid;
}

static const CGFloat kDefaultCellSize = 10.0;

- (instancetype)initWithScreenBounds:(CGRect)bounds cellSize:(CGFloat)cellSize
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _screenBounds = bounds;
  _cellSize = cellSize > 0 ? cellSize : kDefaultCellSize;

  // Calculate grid dimensions, ensuring at least 1 cell
  _width = (NSUInteger)ceil(bounds.size.width / _cellSize);
  _height = (NSUInteger)ceil(bounds.size.height / _cellSize);

  if (_width == 0 || _height == 0) {
    return nil;
  }

  // Allocate and zero-initialize grid
  _grid = (uint8_t *)calloc(_width * _height, sizeof(uint8_t));
  if (!_grid) {
    return nil;
  }

  return self;
}

- (instancetype)initWithScreenBounds:(CGRect)bounds
{
  return [self initWithScreenBounds:bounds cellSize:kDefaultCellSize];
}

- (void)dealloc
{
  if (_grid) {
    free(_grid);
    _grid = NULL;
  }
}

- (void)markFilledWithFrame:(CGRect)frame
{
  if (!_grid || CGRectIsEmpty(frame) || CGRectIsNull(frame)) {
    return;
  }

  // Convert frame coordinates to cell indices, clamping to valid range
  // Use screen bounds origin as reference point
  CGFloat relativeX = frame.origin.x - _screenBounds.origin.x;
  CGFloat relativeY = frame.origin.y - _screenBounds.origin.y;
  CGFloat relativeMaxX = relativeX + frame.size.width;
  CGFloat relativeMaxY = relativeY + frame.size.height;

  // Calculate cell range, clamping to grid bounds
  NSInteger minX = (NSInteger)floor(relativeX / _cellSize);
  NSInteger minY = (NSInteger)floor(relativeY / _cellSize);
  NSInteger maxX = (NSInteger)floor(relativeMaxX / _cellSize);
  NSInteger maxY = (NSInteger)floor(relativeMaxY / _cellSize);

  // Clamp to valid grid indices
  minX = MAX(0, minX);
  minY = MAX(0, minY);
  maxX = MIN((NSInteger)_width - 1, maxX);
  maxY = MIN((NSInteger)_height - 1, maxY);

  // Early exit if completely out of bounds
  if (minX > maxX || minY > maxY) {
    return;
  }

  // Fill cells row by row using memset for efficiency
  NSUInteger fillWidth = (NSUInteger)(maxX - minX + 1);
  for (NSInteger y = minY; y <= maxY; y++) {
    memset(&_grid[y * _width + minX], 1, fillWidth);
  }
}

- (BOOL)isFilledAtPoint:(CGPoint)point
{
  if (!_grid) {
    return NO;
  }

  // Convert point coordinates to cell indices relative to screen bounds
  CGFloat relativeX = point.x - _screenBounds.origin.x;
  CGFloat relativeY = point.y - _screenBounds.origin.y;

  // Calculate cell indices
  NSInteger cellX = (NSInteger)floor(relativeX / _cellSize);
  NSInteger cellY = (NSInteger)floor(relativeY / _cellSize);

  // Check bounds - return NO for out-of-bounds points
  if (cellX < 0 || cellX >= (NSInteger)_width ||
      cellY < 0 || cellY >= (NSInteger)_height) {
    return NO;
  }

  // O(1) lookup in the grid array
  return _grid[cellY * _width + cellX] != 0;
}

- (CGFloat)coverageRatio
{
  if (!_grid || _width == 0 || _height == 0) {
    return -1;
  }

  NSUInteger totalCells = _width * _height;
  NSUInteger filledCells = 0;

  for (NSUInteger i = 0; i < totalCells; i++) {
    if (_grid[i]) {
      filledCells++;
    }
  }

  return (CGFloat)filledCells / (CGFloat)totalCells;
}

@end

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

// Discovery method constants for is_remote key
static NSString *const FBAXDiscoveryMethodRecursive = @"recursive";
static NSString *const FBAXDiscoveryMethodPointGrid = @"point_grid";

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

+ (NSMutableArray<NSDictionary<NSString *, id> *> *)recursiveDescriptionFromElement:(AXPMacPlatformElement *)element token:(NSString *)token nestedFormat:(BOOL)nestedFormat keys:(NSSet<NSString *> *)keys collector:(nullable FBAccessibilityProfilingCollector *)collector coverageGrid:(nullable FBAccessibilityCoverageGrid *)coverageGrid seenPids:(nullable NSMutableSet<NSNumber *> *)seenPids applicationElement:(NSMutableDictionary<NSString *, id> * _Nullable * _Nullable)outApplicationElement
{
  element.translation.bridgeDelegateToken = token;
  pid_t frontmostPid = element.translation.pid;
  if (nestedFormat) {
    NSMutableDictionary<NSString *, id> *appElement = [self.class nestedRecursiveDescriptionFromElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid coverageGrid:coverageGrid seenPids:seenPids];
    if (outApplicationElement) {
      *outApplicationElement = appElement;
    }
    return [@[appElement] mutableCopy];
  }
  return [self.class flatRecursiveDescriptionFromElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid coverageGrid:coverageGrid seenPids:seenPids];
}

+ (NSDictionary<NSString *, id> *)formattedDescriptionOfElement:(AXPMacPlatformElement *)element token:(NSString *)token nestedFormat:(BOOL)nestedFormat keys:(NSSet<NSString *> *)keys collector:(nullable FBAccessibilityProfilingCollector *)collector coverageGrid:(nullable FBAccessibilityCoverageGrid *)coverageGrid
{
  element.translation.bridgeDelegateToken = token;
  pid_t frontmostPid = element.translation.pid;
  if (nestedFormat) {
    return [self.class nestedRecursiveDescriptionFromElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid coverageGrid:coverageGrid seenPids:nil];
  }
  return [self.class accessibilityDictionaryForElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid coverageGrid:coverageGrid seenPids:nil discoveryMethod:FBAXDiscoveryMethodRecursive];
}

// The values here are intended to mirror the values in the old SimulatorBridge implementation for compatibility downstream.
+ (NSDictionary<NSString *, id> *)accessibilityDictionaryForElement:(AXPMacPlatformElement *)element token:(NSString *)token keys:(NSSet<FBAXKeys> *)keys collector:(nullable FBAccessibilityProfilingCollector *)collector frontmostPid:(pid_t)frontmostPid coverageGrid:(nullable FBAccessibilityCoverageGrid *)coverageGrid seenPids:(nullable NSMutableSet<NSNumber *> *)seenPids discoveryMethod:(NSString *)discoveryMethod
{
  // The token must always be set so that the right callback is called
  element.translation.bridgeDelegateToken = token;

  // Track this element's PID if seenPids is provided
  pid_t elementPid = element.translation.pid;
  if (seenPids) {
    [seenPids addObject:@(elementPid)];
  }

  // Increment element count if collector is present
  if (collector) {
    [collector incrementElementCount];
  }

  // Helper macro to include key with JSON serialization if needed (also increments profiling counter)
  #define INCLUDE_IF_KEY(key, expr) do { \
    if ([keys containsObject:key]) { \
      if (collector) { [collector incrementAttributeFetchCountForKey:key]; } \
      values[key] = ensureJSONSerializable(expr); \
    } \
  } while (0)

  NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];

  // Frame is always computed since it's used by multiple keys and coverage grid
  if (collector) { [collector incrementAttributeFetchCountForKey:FBAXKeysFrame]; }
  NSRect frame = element.accessibilityFrame;

  // Role is used by multiple keys and needs processing
  // Check FBAXKeysRole first to assign rawRole, then FBAXKeysType can derive from it
  NSString *role = nil;
  NSString *rawRole = nil;
  if ([keys containsObject:FBAXKeysRole]) {
    if (collector) { [collector incrementAttributeFetchCountForKey:FBAXKeysRole]; }
    rawRole = element.accessibilityRole;
    values[FBAXKeysRole] = ensureJSONSerializable(rawRole);
  }
  if ([keys containsObject:FBAXKeysType]) {
    // Fetch rawRole if not already present
    if (rawRole == nil) {
      if (collector) { [collector incrementAttributeFetchCountForKey:FBAXKeysType]; }
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

  // Mark frame in coverage grid if present (for non-Application elements)
  if (coverageGrid) {
    // Fetch role if not already fetched (needed to identify Application elements)
    if (rawRole == nil) {
      if (collector) { [collector incrementAttributeFetchCountForKey:nil]; }
      rawRole = element.accessibilityRole;
    }
    // Skip Application elements when calculating coverage
    BOOL isApplication = [rawRole isEqualToString:@"AXApplication"] || [rawRole isEqualToString:@"Application"];
    if (!isApplication) {
      [coverageGrid markFilledWithFrame:frame];
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
    if (collector) { [collector incrementAttributeFetchCountForKey:FBAXKeysFrameDict]; }
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
    if (collector) { [collector incrementAttributeFetchCountForKey:FBAXKeysTraits]; }
    NSArray<NSString *> *traits = [self.class traitsFromElement:element];
    values[FBAXKeysTraits] = traits ?: (id)NSNull.null;
  }

  INCLUDE_IF_KEY(FBAXKeysExpanded, @(element.isAccessibilityExpanded));
  INCLUDE_IF_KEY(FBAXKeysPlaceholder, element.accessibilityPlaceholderValue);
  INCLUDE_IF_KEY(FBAXKeysHidden, @(element.isAccessibilityHidden));
  INCLUDE_IF_KEY(FBAXKeysFocused, @(element.isAccessibilityFocused));
  INCLUDE_IF_KEY(FBAXKeysIsRemote, discoveryMethod);

  #undef INCLUDE_IF_KEY

  return [values copy];
}

// This replicates the non-hierarchical system that was previously present in SimulatorBridge.
// In this case the values of frames must be relative to the root, rather than the parent frame.
+ (NSMutableArray<NSDictionary<NSString *, id> *> *)flatRecursiveDescriptionFromElement:(AXPMacPlatformElement *)element token:(NSString *)token keys:(NSSet<NSString *> *)keys collector:(nullable FBAccessibilityProfilingCollector *)collector frontmostPid:(pid_t)frontmostPid coverageGrid:(nullable FBAccessibilityCoverageGrid *)coverageGrid seenPids:(nullable NSMutableSet<NSNumber *> *)seenPids
{
  NSMutableArray<NSDictionary<NSString *, id> *> *values = NSMutableArray.array;
  [values addObject:[self accessibilityDictionaryForElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid coverageGrid:coverageGrid seenPids:seenPids discoveryMethod:FBAXDiscoveryMethodRecursive]];
  for (AXPMacPlatformElement *childElement in element.accessibilityChildren) {
    childElement.translation.bridgeDelegateToken = token;
    NSArray<NSDictionary<NSString *, id> *> *childValues = [self flatRecursiveDescriptionFromElement:childElement token:token keys:keys collector:collector frontmostPid:frontmostPid coverageGrid:coverageGrid seenPids:seenPids];
    [values addObjectsFromArray:childValues];
  }
  return values;
}

+ (NSMutableDictionary<NSString *, id> *)nestedRecursiveDescriptionFromElement:(AXPMacPlatformElement *)element token:(NSString *)token keys:(NSSet<NSString *> *)keys collector:(nullable FBAccessibilityProfilingCollector *)collector frontmostPid:(pid_t)frontmostPid coverageGrid:(nullable FBAccessibilityCoverageGrid *)coverageGrid seenPids:(nullable NSMutableSet<NSNumber *> *)seenPids
{
  NSMutableDictionary<NSString *, id> *values = [[self accessibilityDictionaryForElement:element token:token keys:keys collector:collector frontmostPid:frontmostPid coverageGrid:coverageGrid seenPids:seenPids discoveryMethod:FBAXDiscoveryMethodRecursive] mutableCopy];
  NSMutableArray<NSDictionary<NSString *, id> *> *childrenValues = NSMutableArray.array;
  for (AXPMacPlatformElement *childElement in element.accessibilityChildren) {
    childElement.translation.bridgeDelegateToken = token;
    NSMutableDictionary<NSString *, id> *childValues = [self nestedRecursiveDescriptionFromElement:childElement token:token keys:keys collector:collector frontmostPid:frontmostPid coverageGrid:coverageGrid seenPids:seenPids];
    [childrenValues addObject:childValues];
  }
  values[@"children"] = childrenValues;
  return values;
}

@end

@interface FBAXTranslationRequest : NSObject

@property (nonatomic, copy, readonly) NSString *token;
@property (nonatomic, strong, nullable) SimDevice *device;
@property (nonatomic, strong, nullable) FBAccessibilityProfilingCollector *collector;
@property (nonatomic, strong, nullable) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, nullable) NSNumber *frameCoverage;
@property (nonatomic, strong, nullable) NSNumber *additionalFrameCoverage;
@property (nonatomic, strong, nullable) AXPTranslator *translator;

@end

@implementation FBAXTranslationRequest

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _token = NSUUID.UUID.UUIDString;

  return self;
}

- (AXPTranslationObject *)performWithTranslator:(AXPTranslator *)translator
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (nullable FBAccessibilityElementsResponse *)run:(AXPMacPlatformElement *)element options:(FBAccessibilityRequestOptions *)options error:(NSError **)error
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

#pragma mark - Remote Element Discovery Helpers

/**
 Discover remote elements via grid-based hit-testing.
 Skips PIDs already seen in the main traversal.
 Returns an array of discovered element dictionaries.
 */
- (NSArray<NSDictionary *> *)discoverRemoteElementsWithScreenBounds:(CGRect)screenBounds
                                                       frontmostPid:(pid_t)frontmostPid
                                                           seenPids:(NSSet<NSNumber *> *)seenPids
                                                       coverageGrid:(nullable FBAccessibilityCoverageGrid *)coverageGrid
                                                            options:(FBAccessibilityRequestOptions *)options
{
  FBAccessibilityRemoteContentOptions *remoteOptions = options.remoteContentOptions;
  NSMutableArray<NSDictionary *> *discoveredElements = [NSMutableArray array];
  NSMutableSet<NSValue *> *discoveredFrames = [NSMutableSet set];

  // Always include AXFrame for hit-tested elements (needed for nesting and coverage)
  NSMutableSet<NSString *> *keysWithFrame = [options.keys mutableCopy];
  [keysWithFrame addObject:@"AXFrame"];

  CGFloat stepSize = remoteOptions.gridStepSize > 0 ? remoteOptions.gridStepSize : 50.0;
  CGRect region = CGRectIsNull(remoteOptions.region) ? screenBounds : remoteOptions.region;
  NSUInteger maxPoints = remoteOptions.maxPoints;
  NSUInteger pointCount = 0;

  for (CGFloat y = stepSize; y < region.size.height - stepSize; y += stepSize) {
    for (CGFloat x = stepSize; x < region.size.width - stepSize; x += stepSize) {
      if (maxPoints > 0 && pointCount >= maxPoints) {
        break;
      }

      CGPoint point = CGPointMake(region.origin.x + x, region.origin.y + y);

      // Skip points already covered by native accessibility elements.
      // This dynamically excludes toolbars, nav bars, and other covered regions.
      if (coverageGrid && [coverageGrid isFilledAtPoint:point]) {
        continue;
      }

      pointCount++;

      AXPTranslationObject *hitTranslation = [self.translator objectAtPoint:point displayId:0 bridgeDelegateToken:self.token];
      if (!hitTranslation) {
        continue;
      }

      hitTranslation.bridgeDelegateToken = self.token;
      pid_t hitPid = hitTranslation.pid;

      // Skip if PID was already seen in main traversal
      if ([seenPids containsObject:@(hitPid)]) {
        continue;
      }

      if (hitPid <= 0 || hitPid == frontmostPid) {
        continue;
      }

      AXPMacPlatformElement *hitElement = [self.translator macPlatformElementFromTranslation:hitTranslation];
      if (!hitElement) {
        continue;
      }

      CGRect hitFrame = hitElement.accessibilityFrame;
      NSValue *hitFrameValue = [NSValue valueWithRect:hitFrame];

      if ([discoveredFrames containsObject:hitFrameValue]) {
        continue;
      }

      [discoveredFrames addObject:hitFrameValue];

      // Mark in coverage grid if provided
      if (coverageGrid) {
        [coverageGrid markFilledWithFrame:hitFrame];
      }

      NSDictionary *elemDict = [FBSimulatorAccessibilitySerializer
        accessibilityDictionaryForElement:hitElement
                                    token:self.token
                                     keys:keysWithFrame  // Use keys with AXFrame
                                collector:self.collector
                             frontmostPid:frontmostPid
                             coverageGrid:nil  // Already marked above
                                 seenPids:nil  // Don't track, already filtered
                          discoveryMethod:FBAXDiscoveryMethodPointGrid];
      [discoveredElements addObject:elemDict];
    }

    if (maxPoints > 0 && pointCount >= maxPoints) {
      break;
    }
  }

  return discoveredElements;
}

#pragma mark - Remote Content Processing

/**
 Process remote content discovery and merge with main elements.
 Returns the final response with remote elements merged.
 */
- (FBAccessibilityElementsResponse *)processRemoteContentWithMainElements:(NSMutableArray<NSDictionary<NSString *, id> *> *)mainAppElements
                                                       applicationElement:(NSMutableDictionary<NSString *, id> *)applicationElement
                                                             screenBounds:(CGRect)screenBounds
                                                             frontmostPid:(pid_t)frontmostPid
                                                                 seenPids:(NSSet<NSNumber *> *)seenPids
                                                             coverageGrid:(FBAccessibilityCoverageGrid *)grid
                                                            frameCoverage:(NSNumber *)frameCoverage
                                                       serializationStart:(CFAbsoluteTime)serializationStart
                                                                  options:(FBAccessibilityRequestOptions *)options
{
  FBAccessibilityProfilingCollector *collector = self.collector;

  // Record coverage before remote discovery
  CGFloat coverageBefore = grid ? [grid coverageRatio] : 0;

  // Discover remote elements via grid-based hit-testing
  NSArray<NSDictionary *> *discoveredElements = [self
    discoverRemoteElementsWithScreenBounds:screenBounds
                              frontmostPid:frontmostPid
                                  seenPids:seenPids
                              coverageGrid:grid
                                   options:options];

  // Calculate additional coverage from remote discovery
  NSNumber *additionalFrameCoverage = nil;
  if (grid && discoveredElements.count > 0) {
    CGFloat coverageAfter = [grid coverageRatio];
    CGFloat additionalCoverage = coverageAfter - coverageBefore;
    if (additionalCoverage > 0) {
      additionalFrameCoverage = @(additionalCoverage);
    }
  }

  // Merge remote elements directly into mutable structures (no copying needed)
  if (discoveredElements.count > 0) {
    if (applicationElement) {
      // Append to Application element's children for nested format
      NSMutableArray<NSDictionary<NSString *, id> *> *children = applicationElement[@"children"];
      if (!children) {
        children = [NSMutableArray<NSDictionary<NSString *, id> *> new];
        applicationElement[@"children"] = children;
      }
      [children addObjectsFromArray:discoveredElements];
    } else {
      // Append to flat array directly
      [mainAppElements addObjectsFromArray:discoveredElements];
    }
  }

  return [FBAccessibilityElementsResponse
    responseWithElements:mainAppElements
      serializationStart:serializationStart
               collector:collector
           frameCoverage:frameCoverage
 additionalFrameCoverage:additionalFrameCoverage];
}

#pragma mark - Serialization

- (nullable FBAccessibilityElementsResponse *)run:(AXPMacPlatformElement *)element options:(FBAccessibilityRequestOptions *)options error:(NSError **)error
{
  FBAccessibilityProfilingCollector *collector = self.collector;

  // Get screen bounds for coverage calculation and remote content fetching
  CGRect screenBounds = element.accessibilityFrame;

  // Create coverage grid if requested - it will be populated during traversal
  FBAccessibilityCoverageGrid *grid = nil;
  if (options.collectFrameCoverage) {
    grid = [[FBAccessibilityCoverageGrid alloc] initWithScreenBounds:screenBounds];
  }

  // Track PIDs during traversal for deduplication during remote content discovery
  NSMutableSet<NSNumber *> *seenPids = [NSMutableSet set];

  // Track serialization timing if profiling
  CFAbsoluteTime serializationStart = CFAbsoluteTimeGetCurrent();

  // Serialize elements, passing the grid to be populated during traversal
  NSMutableDictionary<NSString *, id> *applicationElement = nil;
  NSMutableArray<NSDictionary<NSString *, id> *> *mainAppElements = [FBSimulatorAccessibilitySerializer
    recursiveDescriptionFromElement:element
                              token:self.token
                       nestedFormat:options.nestedFormat
                               keys:options.keys
                          collector:collector
                       coverageGrid:grid
                           seenPids:seenPids
                 applicationElement:options.nestedFormat ? &applicationElement : nil];

  // Calculate base coverage after main traversal
  NSNumber *frameCoverage = nil;
  if (grid) {
    CGFloat baseCoverage = [grid coverageRatio];
    if (baseCoverage >= 0) {
      frameCoverage = @(baseCoverage);
    }
  }

  // Check if remote content fetching is enabled
  FBAccessibilityRemoteContentOptions *remoteOptions = options.remoteContentOptions;
  if (!remoteOptions || !self.translator) {
    return [FBAccessibilityElementsResponse
      responseWithElements:mainAppElements
        serializationStart:serializationStart
                 collector:collector
             frameCoverage:frameCoverage
   additionalFrameCoverage:nil];
  }

  pid_t frontmostPid = element.translation.pid;
  return [self processRemoteContentWithMainElements:mainAppElements
                                 applicationElement:applicationElement
                                       screenBounds:screenBounds
                                       frontmostPid:frontmostPid
                                           seenPids:seenPids
                                       coverageGrid:grid
                                      frameCoverage:frameCoverage
                                 serializationStart:serializationStart
                                            options:options];
}

- (instancetype)cloneWithNewToken
{
  return [[FBAXTranslationRequest_FrontmostApplication alloc] init];
}

@end

@interface FBAXTranslationRequest_Point : FBAXTranslationRequest

@property (nonatomic, assign, readonly) CGPoint point;

@end

@implementation FBAXTranslationRequest_Point

- (instancetype)initWithPoint:(CGPoint)point
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _point = point;

  return self;
}

- (AXPTranslationObject *)performWithTranslator:(AXPTranslator *)translator
{
  return [translator objectAtPoint:self.point displayId:0 bridgeDelegateToken:self.token];
}

- (nullable FBAccessibilityElementsResponse *)run:(AXPMacPlatformElement *)element options:(FBAccessibilityRequestOptions *)options error:(NSError **)error
{
  FBAccessibilityProfilingCollector *collector = self.collector;

  // Track serialization timing if profiling
  CFAbsoluteTime serializationStart = CFAbsoluteTimeGetCurrent();

  NSDictionary<NSString *, id> *elements = [FBSimulatorAccessibilitySerializer formattedDescriptionOfElement:element token:self.token nestedFormat:options.nestedFormat keys:options.keys collector:collector coverageGrid:nil];

  return [FBAccessibilityElementsResponse
    responseWithElements:elements
      serializationStart:serializationStart
               collector:collector
           frameCoverage:nil
 additionalFrameCoverage:nil];
}

- (instancetype)cloneWithNewToken
{
  return [[FBAXTranslationRequest_Point alloc] initWithPoint:self.point];
}

@end


@interface FBAXTranslationDispatcher : NSObject <AXPTranslationTokenDelegateHelper>

@property (nonatomic, weak, readonly) AXPTranslator *translator;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t callbackQueue;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, FBAXTranslationRequest *> *tokenToRequest;

@end

@interface FBAccessibilityElement ()
- (instancetype)initWithElement:(AXPMacPlatformElement *)element
                        request:(FBAXTranslationRequest *)request
                     dispatcher:(FBAXTranslationDispatcher *)dispatcher
                      simulator:(FBSimulator *)simulator;
@end

@implementation FBAXTranslationDispatcher

#pragma mark Initializers

- (instancetype)initWithTranslator:(AXPTranslator *)translator logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _translator = translator;
  _logger = logger;
  _callbackQueue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.accessibility_translator.callback", DISPATCH_QUEUE_SERIAL);
  _tokenToRequest = [NSMutableDictionary dictionary];

  return self;
}

#pragma mark Public

- (FBFuture<AXPMacPlatformElement *> *)platformElementWithRequest:(FBAXTranslationRequest *)request
                                                          simulator:(FBSimulator *)simulator
{
  return [FBFuture
    onQueue:simulator.workQueue resolveValue:^ AXPMacPlatformElement * (NSError **error) {
      request.device = simulator.device;
      request.translator = self.translator;
      [self pushRequest:request];
      FBAccessibilityProfilingCollector *collector = request.collector;

      // Record translation timing
      CFAbsoluteTime translationStart = CFAbsoluteTimeGetCurrent();
      AXPTranslationObject *translation = [request performWithTranslator:self.translator];
      if (collector) {
        collector.translationDuration = CFAbsoluteTimeGetCurrent() - translationStart;
      }

      if (translation == nil) {
        [self popRequest:request];
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
      return element;
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
  FBAXTranslationRequest *request = [self.tokenToRequest objectForKey:token];
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
    [device sendAccessibilityRequestAsync:axRequest completionQueue:self.callbackQueue completionHandler:^(AXPTranslatorResponse *innerResponse) {
      response = innerResponse;
      dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
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

#pragma mark - FBAccessibilityElement

@interface FBAccessibilityElement ()
@property (nonatomic, strong, readonly) AXPMacPlatformElement *element;
@property (nonatomic, strong, readonly) FBAXTranslationRequest *request;
@property (nonatomic, strong, readonly) FBAXTranslationDispatcher *dispatcher;
@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, assign) BOOL closed;
@end

@implementation FBAccessibilityElement

- (instancetype)initWithElement:(AXPMacPlatformElement *)element
                        request:(FBAXTranslationRequest *)request
                     dispatcher:(FBAXTranslationDispatcher *)dispatcher
                      simulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) return nil;
  _element = element;
  _request = request;
  _dispatcher = dispatcher;
  _simulator = simulator;
  _closed = NO;
  return self;
}

+ (nullable NSString *)stringValueForKey:(FBAXSearchableKey)key fromElement:(AXPMacPlatformElement *)element
{
  if ([key isEqualToString:FBAXKeysLabel]) {
    return element.accessibilityLabel;
  } else if ([key isEqualToString:FBAXKeysUniqueID]) {
    return element.accessibilityIdentifier;
  } else if ([key isEqualToString:FBAXKeysValue]) {
    id value = element.accessibilityValue;
    return [value isKindOfClass:NSString.class] ? value : nil;
  } else if ([key isEqualToString:FBAXKeysTitle]) {
    return element.accessibilityTitle;
  } else if ([key isEqualToString:FBAXKeysRole]) {
    return element.accessibilityRole;
  } else if ([key isEqualToString:FBAXKeysRoleDescription]) {
    return element.accessibilityRoleDescription;
  } else if ([key isEqualToString:FBAXKeysSubrole]) {
    return element.accessibilitySubrole;
  } else if ([key isEqualToString:FBAXKeysHelp]) {
    return element.accessibilityHelp;
  } else if ([key isEqualToString:FBAXKeysPlaceholder]) {
    return element.accessibilityPlaceholderValue;
  }
  return nil;
}

+ (nullable AXPMacPlatformElement *)findElementWithValue:(NSString *)value
                                                  forKey:(FBAXSearchableKey)key
                                               inElement:(AXPMacPlatformElement *)element
                                                   token:(NSString *)token
                                          remainingDepth:(NSUInteger)remainingDepth
{
  element.translation.bridgeDelegateToken = token;
  NSString *propertyValue = [self stringValueForKey:key fromElement:element];
  if (propertyValue != nil && [propertyValue containsString:value]) {
    return element;
  }
  if (remainingDepth == 0) {
    return nil;
  }
  for (AXPMacPlatformElement *child in element.accessibilityChildren) {
    child.translation.bridgeDelegateToken = token;
    AXPMacPlatformElement *found = [self findElementWithValue:value forKey:key inElement:child token:token remainingDepth:remainingDepth - 1];
    if (found != nil) {
      return found;
    }
  }
  return nil;
}

- (void)close
{
  if (!_closed) {
    _closed = YES;
    [_dispatcher popRequest:_request];
  }
}

- (void)dealloc
{
  [self close];
}

- (nullable FBAccessibilityElementsResponse *)serializeWithOptions:(FBAccessibilityRequestOptions *)options
                                                             error:(NSError **)error
{
  if (_closed) {
    return [[FBSimulatorError describe:@"Cannot serialize a closed element"] fail:error];
  }
  FBAXTranslationRequest *request = self.request;
  if (options.enableProfiling && !request.collector) {
    request.collector = [[FBAccessibilityProfilingCollector alloc] init];
  }
  return [request run:self.element options:options error:error];
}

- (nullable NSString *)stringValueForSearchableKey:(FBAXSearchableKey)key error:(NSError **)error
{
  if (_closed) {
    return [[FBSimulatorError describe:@"Cannot read from a closed element"] fail:error];
  }
  return [FBAccessibilityElement stringValueForKey:key fromElement:self.element];
}

- (BOOL)tapWithError:(NSError **)error
{
  if (_closed) {
    return [[FBSimulatorError describe:@"Cannot tap a closed element"] failBool:error];
  }
  AXPMacPlatformElement *element = self.element;

  NSArray<NSString *> *actionNames = element.accessibilityActionNames;
  if (![actionNames containsObject:@"AXPress"]) {
    return [[FBSimulatorError
      describeFormat:@"Element does not support pressing. Supported: %@",
        [FBCollectionInformation oneLineDescriptionFromArray:actionNames]]
      failBool:error];
  }

  if (![element accessibilityPerformPress]) {
    return [[FBSimulatorError
      describeFormat:@"accessibilityPerformPress did not succeed"]
      failBool:error];
  }

  return YES;
}

- (BOOL)scrollWithDirection:(FBAccessibilityScrollDirection)direction error:(NSError **)error
{
  if (_closed) {
    return [[FBSimulatorError describe:@"Cannot scroll a closed element"] failBool:error];
  }
  AXPMacPlatformElement *element = self.element;
  switch (direction) {
    case FBAccessibilityScrollDirectionDown:
      [element performScrollDownByPageAction];
      return YES;
    case FBAccessibilityScrollDirectionUp:
      [element performScrollUpByPageAction];
      return YES;
    case FBAccessibilityScrollDirectionLeft:
      [element performScrollLeftByPageAction];
      return YES;
    case FBAccessibilityScrollDirectionRight:
      [element performScrollRightByPageAction];
      return YES;
    case FBAccessibilityScrollDirectionToVisible:
      [element performScrollToVisible];
      return YES;
    default:
      return [[FBSimulatorError
        describeFormat:@"Unknown scroll direction %lu", (unsigned long)direction]
        failBool:error];
  }
}

- (BOOL)setValue:(id)value error:(NSError **)error
{
  if (_closed) {
    return [[FBSimulatorError describe:@"Cannot set value on a closed element"] failBool:error];
  }
  AXPMacPlatformElement *element = self.element;
  [element setAccessibilityValue:value];
  return YES;
}

@end

static NSString *const CoreSimulatorBridgeServiceName = @"com.apple.CoreSimulator.bridge";

@interface FBSimulatorAccessibilityCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

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

- (FBFuture<FBAccessibilityElement *> *)accessibilityElementAtPoint:(CGPoint)point
{
  FBSimulator *simulator = self.simulator;
  NSError *error = nil;
  if (![self validateAccessibilityWithError:&error]) {
    return [FBFuture futureWithError:error];
  }
  FBAXTranslationRequest *request = [[FBAXTranslationRequest_Point alloc] initWithPoint:point];
  return [FBSimulatorAccessibilityCommands accessibilityElementWithRequest:request simulator:simulator remediationPermitted:NO];
}

- (FBFuture<FBAccessibilityElement *> *)accessibilityElementForFrontmostApplication
{
  FBSimulator *simulator = self.simulator;
  NSError *error = nil;
  if (![self validateAccessibilityWithError:&error]) {
    return [FBFuture futureWithError:error];
  }
  FBAXTranslationRequest *request = [[FBAXTranslationRequest_FrontmostApplication alloc] init];
  return [FBSimulatorAccessibilityCommands accessibilityElementWithRequest:request simulator:simulator remediationPermitted:YES];
}

- (FBFuture<FBAccessibilityElement *> *)accessibilityElementMatchingValue:(NSString *)value
                                                                   forKey:(FBAXSearchableKey)key
                                                                    depth:(NSUInteger)depth
{
  FBSimulator *simulator = self.simulator;
  NSError *error = nil;
  if (![self validateAccessibilityWithError:&error]) {
    return [FBFuture futureWithError:error];
  }
  FBAXTranslationRequest *request = [[FBAXTranslationRequest_FrontmostApplication alloc] init];
  FBAXTranslationDispatcher *dispatcher = simulator.accessibilityTranslationDispatcher;
  return [[FBSimulatorAccessibilityCommands platformElementWithRequest:request simulator:simulator remediationPermitted:YES]
    onQueue:dispatch_get_main_queue() fmap:^FBFuture *(AXPMacPlatformElement *rootElement) {
      AXPMacPlatformElement *found = [FBAccessibilityElement
        findElementWithValue:value
                      forKey:key
                   inElement:rootElement
                       token:request.token
              remainingDepth:depth];
      if (found == nil) {
        [dispatcher popRequest:request];
        return [[FBSimulatorError
          describeFormat:@"Element with %@ containing '%@' not found within depth %lu",
            key, value, (unsigned long)depth]
          failFuture];
      }
      return [FBFuture futureWithResult:[[FBAccessibilityElement alloc]
        initWithElement:found
                request:request
             dispatcher:dispatcher
              simulator:simulator]];
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

+ (FBFuture<AXPMacPlatformElement *> *)platformElementWithRequest:(FBAXTranslationRequest *)request
                                                        simulator:(FBSimulator *)simulator
                                             remediationPermitted:(BOOL)remediationPermitted
{
  FBAXTranslationDispatcher *dispatcher = simulator.accessibilityTranslationDispatcher;
  return [[dispatcher platformElementWithRequest:request simulator:simulator]
    onQueue:simulator.workQueue fmap:^ FBFuture<AXPMacPlatformElement *> * (AXPMacPlatformElement *element) {
      if (!remediationPermitted) {
        return [FBFuture futureWithResult:element];
      }
      return [[self
        remediationRequiredForSimulator:simulator element:element]
        onQueue:simulator.workQueue fmap:^ FBFuture<AXPMacPlatformElement *> * (NSNumber *remediationRequired) {
          if (!remediationRequired.boolValue) {
            return [FBFuture futureWithResult:element];
          }
          // Pop the stale request/token
          [dispatcher popRequest:request];
          FBAXTranslationRequest *nextRequest = [request cloneWithNewToken];
          return [[self remediateSpringBoardForSimulator:simulator]
            onQueue:simulator.workQueue fmap:^ FBFuture<AXPMacPlatformElement *> * (id _) {
              return [self platformElementWithRequest:nextRequest simulator:simulator remediationPermitted:NO];
            }];
        }];
    }];
}

+ (FBFuture<FBAccessibilityElement *> *)accessibilityElementWithRequest:(FBAXTranslationRequest *)request
                                                             simulator:(FBSimulator *)simulator
                                                  remediationPermitted:(BOOL)remediationPermitted
{
  FBAXTranslationDispatcher *dispatcher = simulator.accessibilityTranslationDispatcher;
  return [[self platformElementWithRequest:request simulator:simulator remediationPermitted:remediationPermitted]
    onQueue:simulator.workQueue map:^FBAccessibilityElement *(AXPMacPlatformElement *element) {
      return [[FBAccessibilityElement alloc]
        initWithElement:element
                request:request
             dispatcher:dispatcher
              simulator:simulator];
    }];
}

+ (FBFuture<NSNumber *> *)remediationRequiredForSimulator:(FBSimulator *)simulator element:(AXPMacPlatformElement *)element
{
  // First perform a quick check, if the accessibility frame is zero, then this is indicative of the problem
  if (CGRectEqualToRect(element.accessibilityFrame, CGRectZero) == NO) {
    return [FBFuture futureWithResult:@NO];
  }
  // Then confirm whether the pid of the translation object represents a real pid within the simulator.
  // If it does not, then it likely means that we got the pid of the crashed SpringBoard.
  // A crashed SpringBoard, means that there is a new one running (or else the Simulator is completely hosed).
  // In this case, the remediation is to restart CoreSimulatorBridge, since the CoreSimulatorBridge needs restarting upon a crash.
  // In all likelihood CoreSimulatorBridge contains a constant reference to the pid of SpringBoard and the most effective way of resolving this is to stop it.
  // The Simulator's launchctl will then make sure that the SimulatorBridge is restarted (just like it does for SpringBoard itself).
  pid_t processIdentifier = element.translation.pid;
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

@end
