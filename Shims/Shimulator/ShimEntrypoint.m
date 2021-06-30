/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import "TestCrashShim/TestCrashShim.h"
#import "TestLoadingShim/FBXCTestMain.h"
#import "TestReporterShim/XCTestReporterShim.h"

__attribute__((constructor)) static void EntryPoint()
{
  
  // Unset so we don't cascade into any other process that might be spawned.
  unsetenv("DYLD_INSERT_LIBRARIES");

  NSLog(@"Start of Shimulator");

  // From TestCrashSim
  FBPrintProcessInfo();
  FBPerformCrashAfter();

  NSLog(@"End of Shimulator");

  FBXCTestReporterShimEntryPoint();

  FBXCTestMainEntryPoint();
}

__attribute__((destructor)) static void ExitPoint()
{
  FBXCTestReporterShimExitPoint();
}
