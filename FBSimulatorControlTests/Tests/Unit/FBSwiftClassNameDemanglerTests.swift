/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

/// The mangled inputs here are real `type` values observed on a live read of the Settings root
/// screen — the population this demangler exists for — plus the degenerate shapes the parser must
/// pass through rather than mistranslate.
final class FBSwiftClassNameDemanglerTests: XCTestCase {

  func testPlainClassNamesDemangleToTheClassName() {
    XCTAssertEqual(
      FBSwiftClassNameDemangler.demangle("_TtC5MyApp11MyTestClass"),
      "MyTestClass"
    )
  }

  func testNestedClassNamesDemangleToTheInnermostClass() {
    XCTAssertEqual(
      FBSwiftClassNameDemangler.demangle("_TtCC5UIKit20ScrollEdgeEffectView12BackdropView"),
      "BackdropView"
    )
    XCTAssertEqual(
      FBSwiftClassNameDemangler.demangle("_TtCC5UIKit20ScrollEdgeEffectView19LuminanceAdjustment"),
      "LuminanceAdjustment"
    )
    XCTAssertEqual(
      FBSwiftClassNameDemangler.demangle("_TtCC5UIKit20ScrollEdgeEffectView10PocketMask"),
      "PocketMask"
    )
  }

  func testGenericClassNamesDemangleToTheClassNotTheArguments() {
    XCTAssertEqual(
      FBSwiftClassNameDemangler.demangle("_TtGC7SwiftUI19UIHostingControllerVS_7AnyView_"),
      "UIHostingController"
    )
    // A multi-parameter generic: the class name is the segment after the module, not the
    // second-to-last segment (which is `_ViewList_View`, an argument).
    XCTAssertEqual(
      FBSwiftClassNameDemangler.demangle(
        "_TtGC7SwiftUI15CellHostingViewGVS_15ModifiedContentVS_14_ViewList_ViewVS_26CollectionViewCellModifier__"
      ),
      "CellHostingView"
    )
    XCTAssertEqual(
      FBSwiftClassNameDemangler.demangle(
        "_TtGC7SwiftUI14_UIHostingViewGVS_15ModifiedContentVS_7AnyViewVS_12RootModifier__"
      ),
      "_UIHostingView"
    )
    XCTAssertEqual(
      FBSwiftClassNameDemangler.demangle(
        "_TtGC5UIKit22UICorePlatformViewHostGVS_32PlatformViewRepresentableAdaptorVS_33InlineSearchBarViewRepresentation__"
      ),
      "UICorePlatformViewHost"
    )
  }

  func testGenericClassScopedByAnAnonymousContextSkipsTheDiscriminator() {
    XCTAssertEqual(
      FBSwiftClassNameDemangler.demangle(
        "_TtGC5UIKitP10$186ea25f022FloatingBarHostingViewVS_20FloatingBarContainer_"
      ),
      "FloatingBarHostingView"
    )
  }

  func testClassNestedInsideAGenericClassDemanglesToTheInnermostClass() {
    XCTAssertEqual(
      FBSwiftClassNameDemangler.demangle(
        "_TtCGC7SwiftUI32NavigationStackHostingControllerVS_7AnyView_P10$1d35df01811HostingView"
      ),
      "HostingView"
    )
  }

  func testPrivateClassNamesDemangleToTheClassNotTheFileDiscriminator() {
    XCTAssertEqual(
      FBSwiftClassNameDemangler.demangle(
        "_TtC5UIKitP33_F83AB3ECBB2C378B4FCEB681A4D7DB7430UIPlatformGlassInteractionView"
      ),
      "UIPlatformGlassInteractionView"
    )
  }

  func testReadableNamesPassThroughUnchanged() {
    for name in ["Button", "StaticText", "Any", "UIButton", "CellHostingView", ""] {
      XCTAssertEqual(FBSwiftClassNameDemangler.demangle(name), name)
    }
  }

  func testUnparseableMangledNamesPassThroughUnchanged() {
    // No length-prefixed segments at all.
    XCTAssertEqual(FBSwiftClassNameDemangler.demangle("_Tt"), "_Tt")
    XCTAssertEqual(FBSwiftClassNameDemangler.demangle("_TtQq_"), "_TtQq_")
    // Every declared length overruns the string.
    XCTAssertEqual(FBSwiftClassNameDemangler.demangle("_TtC99Short"), "_TtC99Short")
  }

  func testOverrunningSegmentIsSkippedWithoutLosingTheParsedOnes() {
    // The trailing length claims more characters than remain; the parsed class name still wins.
    XCTAssertEqual(FBSwiftClassNameDemangler.demangle("_TtC5MyApp7MyClass99"), "MyClass")
  }
}
