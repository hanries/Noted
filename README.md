# Noted

A free, native handwritten notebook prototype for iPad and Mac. No external dependencies, account system, advertising, payments, or backend. Written from scratch; no Stylus Labs code was copied.

## Run

Open `Noted.xcodeproj` in Xcode 26 or newer.

- **Mac:** select the **Noted Mac** scheme and **My Mac**, then Run. Create a new document or open `Samples/Welcome.noted`.
- **iPad Simulator:** select **Noted iPad**, choose an installed iPad simulator, then Run.
- **Physical iPad:** choose your Apple development team under Signing & Capabilities, use a unique bundle identifier if required, select the connected iPad, and Run. Requires iPadOS 17+; Mac target requires macOS 14+.

The initial document picker on Mac is normal: choose New Document or open a `.noted` file. Save with the system File menu. On iPad, the system Files browser handles notebook creation, opening, naming, and moving.

## Prototype features

- Native input: Apple Pencil pressure and coalesced touch samples on iPad, mouse/trackpad on Mac.
- Pen, translucent highlighter, whole-stroke eraser, and single-stroke selection/movement.
- Add/edit/move/delete fixed-size text blocks (Text creates; Move selects).
- Ruled, grid, and blank paper; page insertion, duplication, reordering, deletion.
- Fifty-step in-session undo/redo using toolbar buttons.
- Shared versioned JSON `.noted` format; document-based saving on both platforms.
- Same file can be opened through an iCloud Drive folder selected by the user.

On iPad, Pencil-only input is the default to avoid palm marks. To test using a finger or simulator mouse, turn off **Apple Pencil only** in the grid/paper menu. Choose a tool and draw on the paper. Select **Move** to reposition existing ink or text. Text changes update the document as you type; Done closes the inspector. System autosave still controls disk persistence. Use the magnifying glasses for 100–400% zoom relative to fit-to-window. Enable the hand tool to scroll a zoomed page; turn it off to write or select. Pinch zoom and simultaneous finger navigation while writing are not implemented.

## Sync scope — please read

This version relies on Apple's document APIs and a user-selected iCloud Drive location; it has no private CloudKit container. Save the document to an iCloud Drive folder visible in Files and Finder and open that same file on the second device. Both devices need Noted installed and the same Apple Account.

**End-to-end two-device sync has not been verified.** Await upload/download and close the document on the first device before editing on the other. This prototype does not merge concurrent offline changes. **Recover file versions** exports the current notebook, retained reload copies, and any unresolved versions reported by Apple as separate editable files. It never marks conflicts resolved or replaces the original. This is a recovery aid, not a verified conflict-resolution engine. Keep backups of valuable notes. Cloud storage uses the user's existing iCloud quota; local files do not require iCloud.

## Format

`.noted` files are UTF-8 JSON, with version, title, and pages. Each page stores its paper type, UUID, editable strokes (points, pressure, width, color, highlighter flag), and positioned text blocks. Coordinates use a 768 × 1024 page. File decoding rejects unsupported versions, empty notebooks, duplicate page/object IDs, and invalid stroke geometry. Unsupported files are not silently rewritten.

The format is documented here, but still experimental and subject to explicit versioned migration. A PDF is not used as the editable source of truth.

## Checks

Run `./test-model.sh` for portable save/reopen, stroke selection/movement, and malformed-document checks. Build both schemes for UI compilation checks.

## Not included yet

PDF import/export, pinch zoom, multi-stroke lasso, handwriting recognition, images, audio, live collaboration, automatic conflict merging, production-scale rendering optimization, custom app icon, and an open-source license decision.

Before storing important notes: test Pencil writing and palm rejection on a real iPad, save/reopen and interruption recovery, iCloud switching between devices, conflict handling, and long notebooks. The first canvas fits one page to the window; text blocks have a fixed 300 × 90 area.

## Next milestone

1. Validate one notebook moving iPad → Mac → iPad with edits intact.
2. Add explicit sync/conflict recovery and backup/export.
3. Improve writing with zoom, panning, and multi-stroke selection.
4. Add PDF annotation after the core document workflow is reliable.

## September 10 reliability update

- Text edits enter the document immediately, avoiding draft loss when changing pages or tools.
- Beginning a selection clears the previous drag targets, preventing an old selected stroke from moving with newly selected text.
- Completed drawing/erasing gestures are attached to their original page, including when page selection changes. Pending gestures finish before history operations and when the scene becomes inactive.
- Each document decode has a fresh in-memory identity. A reload clears stale undo/redo and gesture state, even when the newly loaded notebook has identical content.
- On an observed reload, the previous notebook is retained in memory and written atomically into the app's local Application Support `Noted/Recovery` directory. These recovery copies persist across launches and are included by **Recover file versions**. They are not automatically deleted or synced, and may contain private notes from other notebooks opened by this app. A failure to save a recovery copy is reported; export the in-memory copy before closing.
- **Export notebook copy** creates a separate editable backup using the system exporter. Recovery exports do not resolve system conflicts. Export filenames should be checked in the system dialog.
- Zoom buttons and an explicit hand/scroll mode provide navigation on both platforms. Pencil-only remains the default; native touch capture tracks one accepted touch and supports multiple simultaneous touches so rejected fingers do not occupy the sole touch slot.

### Validation and remaining work

Both Mac and iPad Simulator targets build successfully after the update. The ten portable model checks pass. Updated UI behavior has **not** been tested: CoreSimulator was unavailable in the execution environment, and launching the Mac app through computer use was blocked by automatic approval review with a usage-limit error. Previous prototype UI results do not validate these changes.

Reload recovery depends on SwiftUI delivering a document replacement. It cannot guarantee recovery of a version already overwritten by a file provider, recover uncommitted input after a crash, or guarantee that every iCloud conflict is exposed. There is no verified coordinated concurrent-save strategy yet. Avoid simultaneous editing and keep exported backups until physical-device tests pass.

Required manual checks: type then switch tools/pages and reopen; draw/erase at each zoom level; pan without creating ink; switch pages during input; undo/redo after moves and text changes; externally replace an open file and verify recovery and history reset; create an offline iCloud conflict and export both versions. Finally perform iPad → Mac → iPad using one iCloud file with Apple Pencil, a signed physical iPad build, and the same Apple Account. Verify every stroke, text edit, page order, interruption, and recovery copy on both devices. Lasso selection and production-scale rendering remain future work.
