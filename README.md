# Noted

A free, native handwritten notebook app for iPad and Mac. No subscriptions, ads, Noted account, notebook limits, external dependencies, or hosted backend. Editable strokes and text are stored in a shared `.noted` file; PDF is not the source of truth. Still a prototype.

## Run

Open `Noted.xcodeproj` in Xcode 26 or newer.

- **Mac:** select **Noted Mac** and **My Mac**. The Notebooks window provides a searchable local library with previews, New notebook, Import, and Open from Files. Return to it through **File → Notebooks** (Shift–Command–1). Document windows support Mac mouse/trackpad input and standard File saving commands.
- **iPad Simulator:** select **Noted iPad** and an installed iPad simulator. Turn off **Apple Pencil only** under Paper & input to draw using simulated touch input.
- **Physical iPad:** use your Apple development team and a suitable bundle identifier in Signing & Capabilities, then run on the connected device. Requires iPadOS 17+; Mac requires macOS 14+.

Both platforms open a local notebook library. **New notebook** saves directly on the device; no Apple Account, iCloud setup, or file-location prompt is needed. The iPad library uses a coordinated `UIDocument` session; the Mac uses native document windows. Local notebooks live in the app's Documents/Noted folder and are visible in Files/Finder. The library also lists older `.noted` files at the app's Documents root.

## Import and export

- **Library → Import:** create a local notebook from `.noted`, an unlocked PDF, PNG, or JPEG. Preview the first selected page and choose all pages or a range such as `1-3, 5`.
- **Notebook menu → Import pages:** append PDF/image pages to the current notebook. A local recovery copy is saved first; the import is one Undo step.
- **Notebook menu → Export:** save an independent copy as editable `.noted`, PDF, PNG, or JPEG. Choose all pages or a page range; PDF/image exports can omit ruled/grid paper. Image exports produce one file per selected page at 1536 × 2048. Exporting does not move the working notebook.
- PDF and image imports become page backgrounds. New strokes and text remain editable. Existing PDF text, form fields, links, and handwriting are not converted to native Noted objects. Pages fit the existing portrait page size; wide source pages may have margins. Password-protected PDFs are rejected.
- `.noted` keeps original embedded PDF/image bytes and native ink/text. PDF exports draw imported PDF content as PDF content rather than using the screen preview bitmap. Keep the `.noted` original when you want to edit individual strokes later.

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

## Saving, optional shared storage, and recovery

Local storage is the default. **Notebook menu → Storage & other devices** shows the working location and offers **Move notebook** or **Export a separate copy**. A move changes where subsequent edits are saved; export creates an independent copy. A recovery copy is retained before a move. Cancelling an iPad move reopens the original document. Use **Notebooks** on iPad to save and close; a close failure keeps the editor open and reports the error.

Shared storage is optional. Install and sign into a provider separately, enable its Files location on iPad, then choose it using the system picker. On Mac, open that same `.noted` file from the provider's Finder folder. Google Drive, iCloud Drive, and other providers manage their own downloads/uploads. Noted has no provider-specific login, subscription, backend, custom sync engine, or live upload indicator. Provider compatibility, in-place moves, and two-device handoff need testing with each provider before they can be promised.

**On September 14, 2026, the user reported that sequential iPad → Mac → iPad handoff worked.** This predates the current local-library implementation and is not verification of concurrent edits, offline conflicts, or interruption recovery. Close the notebook on one device and wait for the provider to upload/download before opening it elsewhere. Simultaneous editing is not supported.

- On a document reload, the previous in-memory notebook is retained under local Application Support `Noted/Recovery`; undo history resets. iPad backs up before replacing the loaded contents. Save/recovery failures are reported.
- **Recover file versions** exports the current notebook, retained reload copies, and unresolved versions reported by Apple's document system as separate files. It never marks conflicts resolved or replaces the source. iPad refuses to serialize over a document while the system reports an unresolved conflict.
- Recovery copies persist across launches, are not automatically deleted or synced, and can include other notebooks opened by the app. Export important notebooks to a separate location as well.

Recovery cannot restore a version already overwritten by a provider, or guarantee recovery of uncommitted input after a crash. Cloud conflict handling and recovery remain unverified end to end.

## File format

`.noted` is versioned UTF-8 JSON. Version 1 notebooks contain title, pages, paper, editable pressure strokes, and positioned text. Version 2 adds embedded PDF/PNG/JPEG assets and per-page background references. Original media bytes are base64-encoded in the single JSON file; a multi-page PDF is stored once, and each imported page references its source page. There are no external asset paths to break when moving the notebook.

Existing version 1 files remain readable and stay version 1 until media is added. Older Noted builds cannot open version 2. Recovery copies precede appending media to an existing notebook. Unsupported future versions, invalid geometry, duplicate IDs, broken asset references, and corrupt embedded media are rejected instead of silently replaced with blank pages. `Samples/Welcome.noted` remains a version 1 example.

Coordinates use a 768 × 1024 portrait page. Zoom/pan are viewport state and do not alter saved coordinates. Selected-page exports retain only assets used by the selected pages; an embedded PDF still includes its complete source bytes even if only one source page is referenced. Use PDF/image export when sharing only selected content with someone else. Large documents currently decode the entire JSON and embedded assets into memory; the background preview cache is bounded to 64 MB, but production-scale stress testing remains necessary.

## Validation

Run `./test-model.sh` and `./test-transfer.sh` on a Mac with Xcode installed. The transfer checks use native CoreGraphics, ImageIO, and file coordination; they generate local fixtures under ignored `work/TransferQA`.

- **53 model checks:** existing ink/text/undo-related model behavior, viewport and lasso geometry, automatic-page behavior, version 1 compatibility, version 2 media round trips, malformed references, page ranges, subset asset selection, and repeated imports.
- **11 native transfer checks:** PDF page count, one-asset multi-page import, editable annotations round-trip, PDF re-export, PNG/JPEG import and dimensions, selected PDF page preservation, and corrupt import/media rejection.
- Both Mac and iPad simulator builds pass with signing disabled. Native rendered output was visually inspected for upright PDF backgrounds and annotation placement.
- Mac visual testing verified the local library, creation without a location prompt, and saving inline text. The saved JSON independently confirmed the expected text.
- A simulator test caught an overlapping `UIDocument.open` crash on new notebook creation. The session now has a stable view container and a one-time open guard. Its post-fix UI check is pending.
- Further visual import/export, iPad save/reopen, and move/cancel checks are pending: the Mac was locked during testing on September 20. No claim of completed device or provider verification is made.

Earlier builds verified drawing, inline text editing, save/reopen, automatic pages, and zoomed toolbar switching using simulated touch. Those checks do not substitute for testing the current storage flow, native multitouch, or physical Pencil behavior.

## Before release

See [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) for the prioritized release gates and deferred features. Physical Apple Pencil/palm rejection, real multitouch, iPad lifecycle/low-storage failure recovery, large imported PDFs, signed distribution, accessibility, and real two-device provider conflicts still need verification. The app remains a prototype.

Future features include recoverable notebook trash, easier backup restoration, notebook organization, flexible text sizing, additional paper templates, handwriting search, and audio. There is no chosen open-source license yet; no Stylus Labs code was copied.
