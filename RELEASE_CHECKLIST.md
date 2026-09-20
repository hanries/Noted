# Noted release checklist

Noted is still a prototype. Complete the safety and device checks before a public 1.0; a larger UI redesign can follow after these flows are stable.

## Required before shipping

- [ ] **Save and restore reliably.** Verify autosave, backgrounding, force-quit, interruptions, low storage, corrupt files, and failed provider writes. Add an accessible recovery browser with preview/restore and a clear last-save/error state. Recovery must never overwrite the only surviving version.
- [ ] **Manage notebooks safely.** Add library rename, duplicate, and recoverable trash with restore. Keep permanent deletion separate. Search by title already exists; folders can be modest for 1.0.
- [ ] **Finish physical iPad testing.** Test supported Pencil models, pressure, palm rejection, two-finger navigation, Pencil double-tap, lasso movement and Undo, zoomed toolbar hit testing, rotation, hardware keyboard, and typing at every zoom level.
- [ ] **Verify current storage workflows.** Create locally without an Apple Account; type/draw, close/reopen, restart the app; import selected PDF pages and images; export all four formats; move a notebook, cancel a move, deny permission, and disconnect storage during saving. Check source/copy filenames and content independently.
- [ ] **Qualify each shared provider.** Test iCloud Drive and Google Drive on signed iPad and Mac builds, including sequential round trips, offline edits, external replacement, duplicate/conflicting versions, deletion and rename from another device. Preserve both conflicting versions and offer recovery without silent overwrites. Do not advertise verified provider support based on simulator or local-folder tests.
- [ ] **Stress real notebooks.** Test 100+ pages, large PDFs, dense handwriting, repeated import/Undo, fast scrolling, and long sessions on the oldest supported iPad. Measure memory, latency, file size, open/save time, and cancellation responsiveness. Embedded JSON assets currently load as a whole document.
- [ ] **Make essential controls accessible.** Test VoiceOver labels/order, Dynamic Type, contrast, keyboard shortcuts and focus, pointer hit targets, and both supported size classes. Check exported text placement and images against the editor.
- [ ] **Prepare distribution.** Finalize bundle IDs/signing, app icon, app name/version, an explicit license decision, support/contact page, privacy policy, store screenshots and accurate privacy disclosures. Validate a signed archive and run a TestFlight beta before store submission. Recheck current Apple requirements at submission time.

## Useful near-term improvements

- Resize text areas; reliable copy/paste, selection, and hardware-keyboard editing.
- Page overview, page titles/bookmarks, and faster navigation in long notebooks.
- Simple folders/tags and a recent external-notebook list with reconnect handling.
- Restore-from-backup preview and user-controlled backup retention.
- More paper templates after import, save, and editing are stable.

## Can wait until after 1.0

Handwriting recognition/search, audio recording, rich text, collaboration, custom sync, direct cloud-account integrations, and additional proprietary notebook formats. Keep editable `.noted` files as the source of truth.

## Verification status for this change

The README records completed model/native checks and visual tests. Physical-device, provider-account, accessibility, failure-injection, and large-notebook checks above remain open unless explicitly recorded otherwise.

Apple references: [App Review](https://developer.apple.com/app-store/review/), [App privacy details](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy), and [Submitting an app](https://developer.apple.com/app-store/submitting/).
