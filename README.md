# Noted

A free, native handwritten notebook app for iPad and Mac. No subscriptions, ads, Noted account, notebook limits, external dependencies, or hosted backend. Editable strokes and text are stored in a shared `.noted` file; PDF is not the source of truth. Still a prototype.

## Run

Open `Noted.xcodeproj` in Xcode 26 or newer.

- **Mac:** select **Noted Mac** and **My Mac**. The Notebooks window provides New, Open, a starting paper choice, and recent files. Return to it through **File → Notebooks** (Shift–Command–1). Document windows support Mac mouse/trackpad input and standard File saving commands.
- **iPad Simulator:** select **Noted iPad** and an installed iPad simulator. Turn off **Apple Pencil only** under Paper & input to draw using simulated touch input.
- **Physical iPad:** use your Apple development team and a suitable bundle identifier in Signing & Capabilities, then run on the connected device. Requires iPadOS 17+; Mac requires macOS 14+.

On iPadOS 18+, Noted supplies a paper-themed launch screen. Apple's recent-file and Files browser remain available for opening, naming, moving, and sharing documents. iPadOS 17 retains the system launch interface. No iCloud account is required for local notebooks.

## Write and navigate

- **Pen / Highlight:** capture editable strokes. Apple Pencil pressure and coalesced samples are supported on iPad.
- **Erase:** remove whole strokes. **Move:** select and drag one stroke or text block. **Text:** tap to insert a text block; edits update the document as you type. Done closes the inspector. Text areas remain fixed at 300 × 90 page units.
- **Two fingers on iPad:** drag to pan and pinch to zoom, without choosing a navigation tool. Pencil touches are excluded from navigation recognizers. If a finger drawing gesture becomes a two-finger navigation gesture, the unfinished edit is cancelled; navigation itself never enters undo history. Navigation waits while a Pencil stroke is active.
- **Hand:** beside the pen tools, enables one-finger page dragging on iPad or mouse dragging on Mac. Selecting a writing tool exits Hand mode.
- **Mac trackpad:** scroll to pan; pinch to zoom. Mouse-wheel scrolling also pans.
- **Zoom controls:** beside the tools, from fit-to-window to 400%. Tap the percentage to fit/recenter. Panning is bounded so the page cannot be lost offscreen; a fitted page needs little or no panning.
- **Pencil double-tap:** switches between Erase and the previously selected tool. Supported Pencil hardware is required. Noted leaves double-tap disabled when the system preference is Off; otherwise this app maps it to eraser switching.
- **Undo / Redo:** toolbar history retains the last fifty in-session notebook snapshots. A document reload resets history to avoid applying stale snapshots to externally replaced content.

## Pages and templates

Use the sidebar **+** to choose a previewed **Ruled**, **Grid**, or **Blank** template for a new page. Paper & input → Page templates changes the current page's paper without moving or flattening its contents. Page duplication, reordering, and deletion remain in the notebook menu.

**Keep a blank page ready** is enabled by default and can be disabled in Paper & input or the template chooser. When a completed edit adds content to the last page, Noted appends one empty page with the same paper. It keeps you on your current page. Further edits to that page do not create additional empty pages. Undo restores both the edit and its automatic page creation together. This is a paged editor, not an infinitely scrolling canvas; choose the next page in the sidebar when ready.

## Saving, handoff, and recovery

Use Apple's document controls to save locally or in an iCloud Drive folder shared between your devices. Both devices need Noted installed; iCloud Drive handoff requires the same Apple Account and uses its existing storage quota.

**On September 14, 2026, the user reported that the sequential iPad → Mac → iPad workflow works.** This is a user-reported handoff result, not verification of concurrent edits, offline conflicts, or interruption recovery. Wait for uploads/downloads and close the file on one device before editing on the other. Keep exported backups of valuable notes.

- **Export notebook copy** saves a separate editable `.noted` backup through the system exporter.
- On an observed document reload, the previous in-memory notebook is retained and saved atomically under the app's local Application Support `Noted/Recovery` directory. A failure is reported; export the retained in-memory copy before closing.
- **Recover file versions** exports the current notebook, retained reload copies, and unresolved conflict versions reported by Apple as separate files. It never replaces the source or marks system conflicts resolved. Check export filenames in the system dialog.
- Saved recovery copies persist across launches. They are not automatically deleted or synced and can include notes from other notebooks opened by this app.

There is **no custom sync engine, automatic conflict merging, or verified coordinated concurrent-save strategy**. Recovery depends on SwiftUI delivering a document replacement and Apple exposing conflict versions. It cannot guarantee recovery of a version already overwritten by a provider or uncommitted input lost in a crash. Conflict recovery remains unverified end to end.

## File format

`.noted` is version 1 UTF-8 JSON with a title and pages. Each page stores a UUID, paper type, editable strokes (points, pressure, width, color, highlighter flag), and positioned text blocks. Coordinates use a 768 × 1024 page. Viewport zoom and pan are not stored in the document and do not change stroke coordinates.

Decoding rejects unsupported versions, empty notebooks, duplicate page/object IDs, and invalid stroke geometry. Unsupported files are not silently rewritten. The new navigation and automatic pages retain the existing format; no migration is required. `Samples/Welcome.noted` is an example notebook.

## Validation

Run `./test-model.sh`. All **23 checks** passed after the September 14 changes: encoding/decoding, selection geometry, movement, malformed files, anchored zoom, pan bounds, coordinate/pressure mapping, zoom limits, and automatic-page creation/inheritance/round-trip behavior. Both **Noted Mac** and **Noted iPad** simulator builds passed with signing disabled.

Earlier simulator UI testing on iPad Pro 11-inch (M5), iPadOS 26.4 verified creation, Pencil-only rejection of simulated non-Pencil input, drawing with that setting disabled, moving a stroke, text persistence across tool/page switches, adding a page, erasing and Undo, zoom buttons, and close/reopen. The saved JSON independently confirmed the expected content. That testing predates the new native navigation surface and launch UI.

**September 14 visual checks remain pending:** computer control found the Mac locked. The new home screens, gesture recognizers, and template picker have compiled but have not been visually or interactively verified. Model tests do not substitute for native touch or Pencil tests.

### Next device checks

1. With Pen selected and Pencil-only enabled, use two fingers to pan at 200% and pinch around a visible stroke. Write afterward and verify the stroke appears under the Pencil tip.
2. Turn off Pencil-only, begin a finger stroke, then put down a second finger and navigate. The unfinished mark should disappear and no stray ink/text or extra page should be saved. Lift both fingers before writing again.
3. Select Hand and drag with one finger. Verify Mac mouse dragging, trackpad scroll, and pinch. Resize/rotate and check page bounds and drawing coordinates.
4. Double-tap a supported Pencil to erase, then double-tap back. Check the system Off setting and physical pressure/palm rejection.
5. Write on the last page and verify exactly one same-template spare page. Undo/Redo the edit, save/reopen, and test with automatic pages disabled.
6. Test Mac home New/Open/Recent, iPad launch, all three paper previews, and template changes preserving content.
7. Externally replace an open test notebook, verify history reset and exported recovery copies, then test offline iCloud conflicts without risking valuable notes.

## Future work

Multi-stroke lasso, more page templates, continuous multi-page scrolling, PDF import/export, handwriting recognition, images, audio, conflict-resolution UX, production-scale rendering optimization, custom app icon, and an open-source license decision. No Stylus Labs code was copied.
