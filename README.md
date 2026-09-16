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
- **Erase:** remove whole strokes. **Lasso** (dashed box icon): circle strokes and text on a page, lift to select, then drag inside the dashed selection box to move the group. Items enclosed by or crossing the loop are selected. Start a new loop outside the box to replace the selection; tap blank paper or choose another tool to clear it. Movement stays on the same page and preserves spacing, stroke pressure, and object identities. Each completed move is one Undo step; cancelled movement restores the original contents. **Text:** tap blank paper to type in place with an automatically focused cursor, or tap existing text to edit that same block. Edits update the document as you type. Done ends editing; empty new drafts leave no saved block. Text and Lasso accept finger input even when Pencil-only writing is enabled. Text areas remain fixed at 300 × 90 page units.
- **Two fingers on iPad:** drag to pan and pinch to zoom, without choosing a navigation tool. Pencil touches are excluded from navigation recognizers. If a finger drawing gesture becomes a two-finger navigation gesture, the unfinished edit is cancelled; navigation itself never enters undo history. Navigation waits while a Pencil stroke is active.
- **Hand:** beside the pen tools, enables one-finger page dragging on iPad or mouse dragging on Mac. Selecting a writing tool exits Hand mode.
- **Mac trackpad:** scroll to pan; pinch to zoom. Mouse-wheel scrolling also pans.
- **Zoom controls:** beside the tools, from fit-to-window to 400%. Tap the percentage to fit/recenter. Panning is bounded so the page cannot be lost offscreen; a fitted page needs little or no panning.
- **Pencil double-tap:** switches between Erase and the previously selected tool. Supported Pencil hardware is required. Noted leaves double-tap disabled when the system preference is Off; otherwise this app maps it to eraser switching.
- **Undo / Redo:** toolbar history retains the last fifty in-session notebook snapshots. A document reload resets history to avoid applying stale snapshots to externally replaced content.

## Pages and templates

Use the sidebar **+** to choose a previewed **Ruled**, **Grid**, or **Blank** template for a new page. Paper & input → Page templates changes the current page's paper without moving or flattening its contents. Page duplication, reordering, and deletion remain in the notebook menu.

**Add pages as you scroll** is enabled by default and can be disabled in Paper & input or the template chooser. Pages form a vertical stack. Scroll through existing pages; deliberately scrolling beyond the final page adds another empty page with the same paper, including when the last page is blank. Writing or typing does not create pages. A small overscroll threshold prevents tiny edge movements from immediately creating pages. Scroll upward to return to earlier pages, or choose a page in the sidebar. Zooming alone never adds pages. Page creation can be undone separately from edits. Only visible pages are rendered, although very large notebooks still require performance testing.

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

Run `./test-model.sh`. All **45 checks** passed after the September 16 lasso changes: encoding/decoding, selection geometry, movement, malformed files, anchored zoom, pan bounds, coordinate/pressure mapping, zoom limits, and scroll-created page inheritance/round-trip behavior, page-gap hit testing, later-page zoom anchors, and editing existing text without duplicate or placeholder blocks, lasso geometry and boundary crossings, mixed ink/text selection, and group movement/clamping/persistence. Both **Noted Mac** and **Noted iPad** simulator builds passed with signing disabled.

Earlier simulator UI testing on iPad Pro 11-inch (M5), iPadOS 26.4 verified creation, Pencil-only rejection of simulated non-Pencil input, drawing with that setting disabled, moving a stroke, text persistence across tool/page switches, adding a page, erasing and Undo, zoom buttons, and close/reopen. The saved JSON independently confirmed the expected content. That testing predates the new native navigation surface and launch UI.

**September 14–15 follow-up:** Mac UI testing verified the notebook home, a new grid notebook, scrolling to create page 2, drawing on page 2 without adding pages, and Undo removing that stroke. In-place typing was checked on the page: reopening and editing existing text kept one block, dismissing an empty draft saved no placeholder, and saved text survived reopening. Deleting active text dismissed its editor; Undo restored the text. The saved JSON independently confirmed two grid pages and the expected text.

**September 16 creation fix:** the iPad launch button now uses the standard `NewDocumentButton` initializer, which delegates blank-notebook creation to the existing `DocumentGroup` factory. It no longer selects the custom document-preparation overload. This addresses the reported serialization failure and cancelled creation; a [similar initializer failure is reported on Apple’s developer forum](https://developer.apple.com/forums/thread/807014). The `.noted` format and existing files are unchanged.

On the iPad Pro 11-inch (M5), iPadOS 26.4 simulator, New notebook opened a blank ruled page, in-place typing saved text, and closing/reopening the resulting `Untitled 2.noted` restored that text. Both platform builds and all 34 model checks passed again. The fix still needs confirmation on the physical iPad that reported the error. Current iPad scroll-created pages, native multitouch navigation, and physical Pencil behavior remain unverified. Model tests do not substitute for native touch or Pencil tests.

**September 16 lasso and toolbar fix:** Move is now a freehand lasso with a dashed box icon. Zoomed pages previously expanded the native pointer surface beyond the canvas; the pointer surface now has explicit viewport dimensions, canvas hit testing is bounded, and the toolbar stays above it. The prior build reproduced an ignored Erase tap at 195% zoom in the simulator. After the fix, the same coordinate tap selected Erase at 195%; Lasso, Highlight, and Text switched correctly at 400%. The notebook still contained its original one text item and no added strokes. These are simulated touch checks, not physical Pencil verification. Lasso geometry and group movement pass model checks; an end-to-end freehand Pencil lasso still needs physical-device testing.

### Next device checks

1. At 100%, 200%, and 400%, tap every tool with the Apple Pencil and confirm the selected tool changes without creating ink. Circle several strokes and a text area with Lasso, drag the group, Undo/Redo, and save/reopen. With Pen selected and Pencil-only enabled, use two fingers to pan at 200% and pinch around a visible stroke. Write afterward and verify the stroke appears under the Pencil tip.
2. Turn off Pencil-only, begin a finger stroke, then put down a second finger and navigate. The unfinished mark should disappear and no stray ink/text or extra page should be saved. Lift both fingers before writing again.
3. Select Hand and drag with one finger. Verify Mac mouse dragging, trackpad scroll, and pinch. Resize/rotate and check page bounds and drawing coordinates.
4. Double-tap a supported Pencil to erase, then double-tap back. Check the system Off setting and physical pressure/palm rejection.
5. Scroll past the last page and verify a same-template page appears. Draw and type without adding pages; scroll back up. Undo/Redo page creation, save/reopen, and test with automatic pages disabled. Tap text to type in place and edit it again without creating another block.
6. Test Mac home New/Open/Recent, iPad launch, all three paper previews, and template changes preserving content.
7. Externally replace an open test notebook, verify history reset and exported recovery copies, then test offline iCloud conflicts without risking valuable notes.

## Future work

More page templates, PDF import/export, handwriting recognition, images, audio, conflict-resolution UX, production-scale rendering optimization, custom app icon, and an open-source license decision. No Stylus Labs code was copied.
