/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorWindowTiler.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLaunchInfo.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorPredicates.h"
#import "FBSimulatorWindowHelpers.h"
#import "FBSimulatorWindowTilingStrategy.h"
#import "FBProcessInfo.h"

@interface FBSimulatorWindowTiler ()

@property (nonatomic, strong, readwrite) FBSimulator *simulator;
@property (nonatomic, strong, readwrite) id<FBSimulatorWindowTilingStrategy> strategy;

@end

@implementation FBSimulatorWindowTiler

+ (instancetype)withSimulator:(FBSimulator *)simulator strategy:(id<FBSimulatorWindowTilingStrategy>)strategy
{
  FBSimulatorWindowTiler *tiler = [FBSimulatorWindowTiler new];
  tiler.simulator = simulator;
  tiler.strategy = strategy;
  return tiler;
}

- (CGRect)placeInForegroundWithError:(NSError **)error
{
  if (!AXIsProcessTrusted()) {
    return [[FBSimulatorError describe:@"Current process is untrusted"] failRect:error];
  }
  id<FBProcessInfo> processInfo = self.simulator.launchInfo.simulatorProcess;
  if (!processInfo) {
    return [[[FBSimulatorError describe:@"Cannot find Window ID"] inSimulator:self.simulator] failRect:error];
  }

  AXUIElementRef applicationElement = AXUIElementCreateApplication(processInfo.processIdentifier);
  if (!applicationElement) {
    return [[[FBSimulatorError describe:@"Could not get an Application Element for process"] inSimulator:self.simulator] failRect:error];
  }

  // Get the Window
  AXUIElementRef windowElement = NULL;
  if (AXUIElementCopyAttributeValue(applicationElement, (CFStringRef) NSAccessibilityFocusedWindowAttribute, (CFTypeRef *) &windowElement) != kAXErrorSuccess) {
    return [[[FBSimulatorError describe:@"Could not get the Window Element for the forground Simulator"] inSimulator:self.simulator] failRect:error];
  }

  // Get the size of the window
  CGSize size = CGSizeZero;
  AXValueRef sizeValue = NULL;
  if (AXUIElementCopyAttributeValue(windowElement, (CFStringRef) NSAccessibilitySizeAttribute, (CFTypeRef *) &sizeValue) != kAXErrorSuccess) {
    return [[[FBSimulatorError describe:@"Could not get the size of the Window element"] inSimulator:self.simulator] failRect:error];
  }
  if (!AXValueGetValue(sizeValue, kAXValueCGSizeType, (void *) &size)) {
    return [[[FBSimulatorError describe:@"Could not extract the Size struct from the value"] inSimulator:self.simulator] failRect:error];
  }

  // Position at the appropriate position.
  NSError *innerError = nil;
  CGRect frame = [self bestFittingWindowOfSize:size withError:&innerError];
  if (CGRectIsNull(frame)) {
    return [[[[FBSimulatorError describe:@"Could not find the best fit for the tiled window"] inSimulator:self.simulator] causedBy:innerError] failRect:error];
  }

  // Only the position needs to be set as the Size of the Window is fixed.
  AXValueRef positionValue = AXValueCreate(kAXValueCGPointType, (void *) &(frame.origin));
  if (AXUIElementSetAttributeValue(windowElement, (CFStringRef) NSAccessibilityPositionAttribute, (CFTypeRef *) positionValue) != kAXErrorSuccess) {
    return [[[FBSimulatorError describe:@"Could not set the position for the Window element"] inSimulator:self.simulator] failRect:error];
  }

  // Bring to the front
  if (AXUIElementSetAttributeValue(applicationElement, (CFStringRef) NSAccessibilityFrontmostAttribute, kCFBooleanTrue) != kAXErrorSuccess) {
    return [[[FBSimulatorError describe:@"Could not make Simulator Application frontmost"] inSimulator:self.simulator] failRect:error];
  }

  return frame;
}

- (CGRect)bestFittingWindowOfSize:(CGSize)size withError:(NSError **)error
{
  CGSize displaySize = CGSizeZero;
  if (![FBSimulatorWindowHelpers displayIDForSimulator:self.simulator cropRect:NULL screenSize:&displaySize]) {
    return [[FBSimulatorError describe:@"Could not get the Screen Bounds"] failRect:error];
  }
  return [self.strategy targetPositionOfWindowWithSize:size inScreenSize:displaySize withError:error];
}

@end
