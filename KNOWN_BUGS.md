# Known Bugs and Issues

## Active Bugs 🐛

### 1. PDF Editor Text Input Focus Issue
**Status**: Active
**Priority**: Medium

**Description**: The text input field in the PDF Editor's right sidebar does not properly receive keyboard focus when clicked. Users may have difficulty typing text for text annotations.

**Workaround**: Click directly in the text field multiple times, or tab into the field.

**Related Files**:
- `PDFEditorView.swift` (FocusableTextField, KeyEventHandlerView)

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

**Summary**: 9 of 10 identified issues have been resolved, including:
- Centralized error logging
- Metadata storage data loss prevention
- Video thumbnail race conditions
- File descriptor leaks
- Deprecated API usage
- Core error handling throughout the app
- Loupe tool drag functionality (ImageEditor)

---

## How to Report Bugs

If you encounter a bug:
1. Check if it's already listed above
2. Create a GitHub issue with:
   - Steps to reproduce
   - Expected vs actual behavior
   - macOS version
   - Screenshots if applicable
