# Focused editor build

The target is a fluid iPad writing session with editable Mac counterparts. Existing notebooks and optional local/shared storage remain supported.

1. **Editor controls:** compact Pen, Pencil, Eraser, Selection, Text; tap an active tool for anchored settings; remember color/width per writing tool; visible Undo/Redo, Insert and Export; page sidebar hidden initially on iPad.
2. **Canvas and navigation:** separate live ink from committed page rendering; avoid repainting page thumbnails during an unfinished stroke; add cancellable iPad pan momentum, preserve two-finger pinch anchors, and prevent momentum from adding pages.
3. **Selection and erasing:** rectangle/freehand selection of editable objects; move, resize, copy/paste, duplicate and delete; one Undo per completed action; whole-stroke and partial-stroke erasing.
4. **Text and insertion:** type on the page, wrap and grow text, resize text width; insert movable images from Files/Photos; preserve image assets and geometry in editable exports. PDF import remains background pages.
5. **Validation:** model geometry/eraser/compatibility checks, native export checks, both builds; user performs the Mac/iPad workflow checks. Real Pencil latency, palm rejection, multitouch and device/provider round trips remain separate physical checks.

Acceptance session: create locally, write, change color, erase part of a stroke, select/move/resize an equation, type beside it, insert an image, scroll to a new page, Undo/Redo, export and reopen.

No additional recognition, audio, collaboration or custom cloud integration in this milestone. App-store readiness remains tracked in RELEASE_CHECKLIST.md.


## Build status

Steps 1–4 are implemented as a first checkpoint build. Step 5 passed 75 model checks, 16 native transfer checks, and both platform builds. Usability, real Pencil behavior and provider round trips await the user's manual checks. Do not equate these builds/tests with a smoothness sign-off.

## Manual checkpoints

### A — Writing and navigation (try first)

1. Create a local notebook. Write with Pen; tap the selected Pen again and change color/thickness.
2. Switch to Pencil, set a different color/width, and switch back. Each should retain its settings.
3. Pinch to zoom, pan with two fingers, lift, then touch to stop momentum. Switch tools at 100%, 200% and 400%.
4. Scroll beyond the last page deliberately. A new page should appear; momentum alone should not add pages.
5. Close/reopen. Check strokes and settings are retained.

Feedback: delayed or missed taps, ink lag, unwanted marks, zoom jumps, excessive scrolling, tool-palette size.

### B — Erase and rearrange

1. Draw a long line; erase its middle using Part of stroke. Undo/Redo.
2. Choose Whole stroke; erase the same line and Undo.
3. Select several marks using Rectangle, then Freehand. Move them, resize from the circular corner, duplicate and delete. Undo each action.
4. Copy a selection, open another page/notebook, and use Insert → Paste selection.

Feedback: selection boundaries, accidental selection/resize, handle size, movement accuracy and Undo predictability.

### C — Type, insert and export

1. Tap with Text; type multiple lines. Finish and tap the same text again. Adjust width using Move / resize.
2. Insert an image from Files or Photos, move/resize it, then Undo/Redo.
3. Import PDF pages; annotate them. Export PDF, an image, and an editable notebook.
4. Open the exported notebook and confirm image, Pencil and text can still be edited. Compare PDF/image output with the page.

Feedback: keyboard/caret behavior, wrapping, photo/file picker behavior, export appearance and reopen failures.
