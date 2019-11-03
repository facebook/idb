/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */


#import "FBRuntimeTools.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

void *FBRetrieveSymbolFromBinary(const char *binary, const char *name)
{
  void *handle = dlopen(binary, RTLD_LAZY);
  NSCAssert(handle, @"%s could not be opened", binary);
  void *pointer = dlsym(handle, name);
  NSCAssert(pointer, @"%s could not be located", name);
  return pointer;
}

void *FBRetrieveXCTestSymbol(const char *name)
{
  Class XCTestClass = objc_lookUpClass("XCTestCase");
  NSCAssert(XCTestClass != nil, @"XCTest should be already linked", XCTestClass);
  NSString *XCTestBinary = [NSBundle bundleForClass:XCTestClass].executablePath;
  const char *binaryPath = XCTestBinary.UTF8String;
  NSCAssert(binaryPath != nil, @"XCTest binary path should not be nil", binaryPath);
  return FBRetrieveSymbolFromBinary(binaryPath, name);
}
