# Calibration Automation Plan

## Overview
This document outlines the plan for fully automated calibration verification using image analysis.

## Current Status
✅ **Completed:**
- Rust gRPC client for sending tap events
- Coordinate system mapping (with Y-inversion and offset)
- Screenshot capture via idb_companion
- Progressive screenshot saving during calibration

🚧 **Planned:**
- Automated image analysis for verification
- Pass/fail determination without manual inspection

## Image Analysis Implementation Plan

### Phase 1: Color-Based Target Detection

#### Blue Target Detection (Unhit)
```rust
// Detect blue circular regions
// Color range: RGB(80-100, 140-160, 245-255)
// Features:
// - Circular shape with '+' symbol
// - Approximate radius: 30-40 pixels
// - Blue gradient from center to edge
```

#### Red Circle Detection (Hit)
```rust
// Detect red circular regions with numbers
// Color range: RGB(245-255, 40-60, 40-60)
// Features:
// - Red circle with white number inside
// - Number indicates hit order (1-5)
// - Same size as blue targets
```

### Phase 2: Text Recognition

#### Counter Detection
```rust
// Parse "Tapped: X/5" from top overlay
// Location: Top-left corner in dark overlay
// Method: Template matching or simple OCR
// Format: "Tapped: {current}/{total}"
```

#### Tap History Parsing
```rust
// Extract from bottom overlay
// Format: "[{index}] ({x}, {y}) - {MISS|HIT}"
// Color coding: Yellow = miss, Green = hit
```

### Phase 3: Verification Logic

```rust
pub struct VerificationResult {
    pub all_targets_hit: bool,
    pub correct_positions: bool,
    pub counter_correct: bool,
    pub details: Vec<TargetVerification>,
}

pub struct TargetVerification {
    pub expected_position: (f64, f64),
    pub detected_position: Option<(u32, u32)>,
    pub was_hit: bool,
    pub hit_order: Option<u32>,
    pub distance_error: f64,
}
```

### Phase 4: Implementation Steps

1. **Basic Color Detection**
   - Implement HSV color space conversion
   - Create masks for blue and red regions
   - Find contours and filter by circularity

2. **Shape Analysis**
   - Validate circular shapes
   - Check for '+' symbol in blue targets
   - Extract bounding boxes

3. **Number Recognition**
   - Isolate white regions within red circles
   - Use template matching for digits 1-5
   - Or implement simple digit recognition

4. **Integration**
   - Combine all detection results
   - Calculate success metrics
   - Generate detailed reports

## Algorithm Pseudocode

```
1. Load screenshot
2. Convert to HSV color space
3. Create masks:
   - blue_mask = inRange(hsv, blue_lower, blue_upper)
   - red_mask = inRange(hsv, red_lower, red_upper)
4. Find contours in each mask
5. For each contour:
   - Check if circular (using contour area vs perimeter)
   - Extract center point
   - For red circles: extract and recognize number
6. Parse text overlays for counter and history
7. Compare detected targets with expected positions
8. Return verification results
```

## Testing Strategy

1. **Unit Tests**
   - Test color detection with sample images
   - Test shape detection algorithms
   - Test number recognition

2. **Integration Tests**
   - Test full pipeline with known screenshots
   - Test edge cases (partially visible targets, etc.)

3. **End-to-End Tests**
   - Run full calibration sequence
   - Verify all screenshots automatically
   - Generate pass/fail report

## Future Enhancements

1. **Machine Learning**
   - Train CNN for more robust target detection
   - Handle various lighting conditions
   - Support different UI themes

2. **Advanced Features**
   - Real-time video analysis
   - Performance metrics (tap accuracy, timing)
   - Automatic retry on failures

3. **Reporting**
   - HTML reports with annotated screenshots
   - JSON export for CI/CD integration
   - Historical trend analysis