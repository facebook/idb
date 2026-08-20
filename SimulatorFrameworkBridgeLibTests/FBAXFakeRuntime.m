/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAXFakeRuntime.h"

static NSString *const kAXElementType = @"XC_kAXXCAttributeElementType";
static NSString *const kAXLabel = @"XC_kAXXCAttributeLabel";
static NSString *const kAXChildren = @"XC_kAXXCAttributeChildren";

@implementation FBAXFakeElement

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _attributes = @{};
  _children = @[];
  _readStatus = FBAXReadStatusRead;
  return self;
}

+ (instancetype)readable:(NSString *)elementType
{
  FBAXFakeElement *element = [self new];
  element.attributes = @{kAXElementType : elementType, kAXLabel : elementType};
  return element;
}

+ (instancetype)applicationUnavailable
{
  FBAXFakeElement *element = [self new];
  element.readStatus = FBAXReadStatusApplicationUnavailable;
  return element;
}

+ (instancetype)applicationNotResponding
{
  FBAXFakeElement *element = [self new];
  element.readStatus = FBAXReadStatusApplicationNotResponding;
  return element;
}

+ (instancetype)failed:(nullable NSError *)error
{
  FBAXFakeElement *element = [self new];
  element.readStatus = FBAXReadStatusFailed;
  element.readError = error;
  return element;
}

@end

@implementation FBAXFakeRuntime
{
  NSUInteger _translatorReadCount;
  NSArray<NSNumber *> *_lastTranslatorAttributes;
  NSUInteger _snapshotCount;
  NSArray<NSString *> *_lastSnapshotAttributeNames;
}

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _applicationElements = [NSMutableDictionary dictionary];
  _automationModeWrites = [NSMutableArray array];
  _hitTestOutcome = [FBAXHitTestOutcome empty];
  _windowServerOutcome = [FBAXFrontmostOutcome unresolved:@"no window-server outcome configured"];
  _runningBoardOutcome = [FBAXFrontmostOutcome unresolved:@"no running-board outcome configured"];
  _writeOutcome = [FBAXWriteOutcome written];
  return self;
}

#pragma mark - FBAXRuntime

- (nullable id)applicationElementForProcessIdentifier:(pid_t)pid
{
  return self.applicationElements[@(pid)];
}

// The snapshot API's own keys, spelled here rather than shared with the service so a test fails if the
// service starts reading a different key than the runtime answers with.
static NSString *const kFakeSnapshotAttributes = @"UIAccessibilitySnapshotKeyAttributes";
static NSString *const kFakeSnapshotChildren = @"UIAccessibilitySnapshotKeyChildren";

// The attribute numbers this fake converts names to. Arbitrary, and deliberately not the runtime's:
// nothing above the seam may depend on a particular number, so a fake that used the real ones would let
// a hardcoded number pass.
static NSNumber *FBAXFakeAttributeNumber(NSUInteger index)
{
  return @(9000 + (NSInteger)index);
}

// Rebuilds one fake element as a snapshot node — attributes keyed by number, children nested under the
// snapshot's own key rather than exposed as an attribute.
static NSDictionary *FBAXFakeSnapshotNode(FBAXFakeElement *element,
                                          NSDictionary<NSString *, NSNumber *> *numbersByName
)
{
  NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
  for (NSString *name in element.attributes) {
    NSNumber *number = numbersByName[name];
    // Only what was asked for comes back, as the real snapshot does — an attribute outside the request
    // has no number, so it has no key to be answered under.
    if (number) {
      attributes[number] = element.attributes[name];
    }
  }
  NSMutableArray *children = [NSMutableArray array];
  for (FBAXFakeElement *child in element.children) {
    [children addObject:FBAXFakeSnapshotNode(child, numbersByName)];
  }
  return @{kFakeSnapshotAttributes : attributes, kFakeSnapshotChildren : children};
}

- (nullable id)snapshotOfElement:(id)element
                  attributeNames:(NSArray<NSString *> *)names
                   namesByNumber:(NSDictionary<NSNumber *, NSString *> *_Nullable *_Nonnull)namesByNumber
                           error:(NSError **)error
{
  _snapshotCount++;
  _lastSnapshotAttributeNames = [names copy];
  if (self.snapshotError) {
    if (error) {
      *error = self.snapshotError;
    }
    return nil;
  }
  if (self.snapshotAnswersNothing) {
    return nil;
  }

  NSMutableDictionary<NSNumber *, NSString *> *inverse = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString *, NSNumber *> *forward = [NSMutableDictionary dictionary];
  [names enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, BOOL *stop) {
    NSNumber *number = FBAXFakeAttributeNumber(index);
    inverse[number] = name;
    forward[name] = number;
  }];
  *namesByNumber = inverse;
  return FBAXFakeSnapshotNode(element, forward);
}

- (BOOL)getRect:(CGRect *)rect fromValue:(id)value
{
  // The live runtime unwraps an AXValue, which cannot be constructed here. An `NSValue`-boxed rect stands
  // in for one: what the caller is being tested on is that it asks the seam rather than that it knows the
  // CFType. Anything else answers NO, which is the branch that matters — an unrecognised value must leave
  // the rect alone rather than produce a zero frame.
  if (!rect || ![value isKindOfClass:NSValue.class]) {
    return NO;
  }
  NSValue *boxed = value;
  if (strcmp(boxed.objCType, @encode(CGRect)) != 0) {
    return NO;
  }
  [boxed getValue:rect size:sizeof(*rect)];
  return YES;
}

- (FBAXReadOutcome *)readAttributes:(NSArray<NSString *> *)attributes ofElement:(id)element
{
  // Recorded before the outcome switch, so a read that fails still evidences what it asked for.
  _lastReadAttributes = [attributes copy];
  if (self.readRaiseReason) {
    [NSException raise:NSInternalInconsistencyException format:@"%@", self.readRaiseReason];
  }
  FBAXFakeElement *fake = element;
  switch (fake.readStatus) {
    case FBAXReadStatusRead:
      break;
    case FBAXReadStatusApplicationUnavailable:
      return [FBAXReadOutcome applicationUnavailable];
    case FBAXReadStatusApplicationNotResponding:
      return [FBAXReadOutcome applicationNotResponding];
    case FBAXReadStatusFailed:
    default:
      return [FBAXReadOutcome failed:fake.readError];
  }
  // Children come back as element handles, exactly as the live runtime returns them — the tree walk is
  // what turns them into nested dictionaries, and covering that is the point.
  NSMutableDictionary<NSString *, id> *read = [fake.attributes mutableCopy];
  read[kAXChildren] = fake.children;
  return [FBAXReadOutcome read:read];
}

- (FBAXHitTestOutcome *)hitTestAtPoint:(CGPoint)point processIdentifier:(pid_t)pid
{
  _hitTestCount++;
  _lastHitTestPoint = point;
  _lastHitTestProcessIdentifier = pid;
  return self.hitTestOutcome;
}

- (FBAXWriteOutcome *)performAction:(FBAXAction)action onElement:(id)element
{
  _performCount++;
  _lastPerformedAction = action;
  _lastWrittenElement = element;
  return self.writeOutcome;
}

- (FBAXWriteOutcome *)setValue:(id)value onElement:(id)element
{
  _setValueCount++;
  _lastWrittenElement = element;
  _lastWrittenValue = value;
  return self.writeOutcome;
}

- (FBAXFrontmostOutcome *)windowServerFrontmost
{
  _windowServerCount++;
  return self.windowServerOutcome;
}

- (nullable NSDictionary<NSNumber *, id> *)translatorAttributes:(NSArray<NSNumber *> *)attributes
                                                      ofElement:(id)element
{
  _translatorReadCount++;
  _lastTranslatorAttributes = [attributes copy];
  return self.translatorAttributeValues;
}

- (FBAXFrontmostOutcome *)runningBoardFrontmost
{
  _runningBoardCount++;
  return self.runningBoardOutcome;
}

#pragma mark Automation mode

- (BOOL)automationModeEnabled
{
  return self.automationMode;
}

- (BOOL)setAutomationModeEnabled:(BOOL)enabled
{
  [self.automationModeWrites addObject:@(enabled)];
  if (!self.automationModeWriteFails) {
    self.automationMode = enabled;
  }
  // Read back, exactly as the live runtime does: what a caller learns is the state afterwards, not that
  // the write was attempted.
  return self.automationMode;
}

@end
