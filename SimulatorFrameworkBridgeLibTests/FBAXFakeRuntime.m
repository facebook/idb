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
