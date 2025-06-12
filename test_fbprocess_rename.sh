#!/bin/bash
# Test script to verify FBProcess rename eliminates the objc warning

echo "Building FBControlCore framework to test FBProcess rename..."

# Build just the FBControlCore framework
xcodebuild -project FBSimulatorControl.xcodeproj \
  -scheme FBControlCore \
  -sdk macosx \
  build \
  2>&1 | tee build_output.log

echo ""
echo "Checking for FBProcess duplicate class warning..."
if grep -q "Class FBProcess is implemented in both" build_output.log; then
  echo "❌ WARNING STILL PRESENT: The objc duplicate class warning for FBProcess still exists"
  grep "Class FBProcess is implemented in both" build_output.log
else
  echo "✅ SUCCESS: No duplicate FBProcess class warning found!"
fi

echo ""
echo "Checking for any remaining FBProcess references..."
grep -n "\\bFBProcess\\b" FBControlCore/Tasks/FBProcess.{h,m} | grep -v "FBIDBProcess" | head -10

# Clean up
rm -f build_output.log

echo ""
echo "Done!"