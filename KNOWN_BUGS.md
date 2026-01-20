# Known Bugs and Issues

## Active Bugs 🐛

### 1. Loupe Tool - Drag Still Not Working Properly
**Status**: ⚠️ Partially Fixed  
**Priority**: High  
**Description**: While the loupe tool improvements were made (separate target/center, arrow rendering), dragging existing loupes still doesn't work smoothly. Attempts were made to fix drag detection, but the issue persists.

**Current Behavior**:
- Loupe moves in very small increments when attempting to drag
- Not smooth/continuous movement as expected

**Related Files**:
- `ImageEditor.swift` (lines 496-525, drag gesture handling)

---

## Deferred Issues 📋

### 2. Multi-Monitor Coordinate Conversion Bugs
**Status**: Deferred  
**Priority**: Medium  
**Reason**: Requires multi-monitor setup for proper testing

**Description**: Screen recording border overlay may not position correctly on secondary monitors due to coordinate system conversion issues.

**Related Files**:
- `ScreenRecorder.swift` (lines 276-422)

---

### 3. Memory Management for Large Images
**Status**: Deferred  
**Priority**: Medium  
**Reason**: Optimization, not critical for core functionality

**Description**: ImageEditor loads full-resolution images without size limits, potentially causing crashes with very large (4K+) screenshots.

**Related Files**:
- `ImageEditor.swift` (renderImage method)

---

### 4. Hash Computation Performance
**Status**: Deferred  
**Priority**: Low  
**Reason**: Performance optimization, not a bug

**Description**: Sequential hash computation for large libraries can be slow on initial load. Could benefit from batching and parallel processing.

**Related Files**:
- `ScreenshotLibrary.swift` (kickOffHashing method)

---

### 5. Permission Check Timing
**Status**: Deferred  
**Priority**: Low  
**Reason**: UX improvement, not a bug

**Description**: Permission dialogs appear after UI is already displayed, leading to poor first-run experience.

**Related Files**:
- `ScreenshotManagerApp.swift` (lines 92-111)

---

## Fixed Issues ✅

For a complete list of resolved issues, see:
- `../brain/45b2afbd-71db-4b0f-a652-e8c4bf897d92/walkthrough.md`
- `../brain/45b2afbd-71db-4b0f-a652-e8c4bf897d92/issues_summary.md`

**Summary**: 8 of 10 identified issues have been resolved, including:
- Centralized error logging
- Metadata storage data loss prevention
- Video thumbnail race conditions
- File descriptor leaks
- Deprecated API usage
- Core error handling throughout the app

---

## How to Report Bugs

If you encounter a bug:
1. Check if it's already listed above
2. Create a GitHub issue with:
   - Steps to reproduce
   - Expected vs actual behavior
   - macOS version
   - Screenshots if applicable
