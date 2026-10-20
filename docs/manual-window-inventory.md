# Manual QA window inventory

Use the separate callback helper to inspect window metadata without activating
Draftly QA. This check does not use Accessibility or send events to the QA app.

## Setup

1. Build and register the isolated QA app and the callback helper in a manual
   session. Do not register the habitual Draftly URL scheme to the QA app.
2. Confirm that the QA bundle ID is `com.andrestobelem.draftly.engine-qa` and that
   its `DraftlyUITesting` Info key is true.
3. Open the callback helper. Keep its URL field for the existing neutral URL
   tests. Enable **Monitor QA windows (read only)**.

The helper reads Core Graphics window metadata once per second. **Refresh window
inventory** takes the same reading on demand. Neither operation opens a QA URL,
activates QA, changes its selection, or creates a QA window. Turn the monitor off
when the check ends. No records are written to disk.

## Check a cold URL and source-window close

1. Record the displayed QA PID and visible normal-window count.
2. Use the helper URL field to send the neutral QA action URL. This is an
   explicit launch operation. It is separate from the read-only inventory.
3. After the action finishes, inspect the inventory without activating QA.
   Record each window number and title in the textual validation summary.
4. Close the source window during the separate manual interaction. Return to
   the helper. Do not click or activate QA merely to identify a window.
5. Compare the PID, count, and window numbers. A new window number indicates a
   different window. A retained number with a changed title indicates the same
   window. Check whether an extra normal window named `Untitled` appears.
6. Repeat with the source kept open. Compare this control case with the close
   case. Do not treat an inventory observation as proof of the selected draft.

## Interpretation and limits

The displayed normal-window count includes only on-screen records at layer zero.
The total count also includes off-screen and nonzero-layer records. Each row
shows its layer and visibility, so a panel is not counted silently as a normal
window. The helper shows at most ten rows per QA process and reports extra rows.

Window titles can be absent because of macOS privacy rules. The helper reports
`<title unavailable>` and does not request Screen Recording permission. An empty
reported title is shown as `<empty title>`. Neither state proves that the draft
is Untitled. Core Graphics metadata cannot prove editor content, selection,
focus, or the cause of a window creation. Those checks need a separate manual
inspection or an app-level state check.

## Headless classifier check

After the coordinator builds the helper, run its executable with
`--window-inventory-self-test`. It exits before it creates NSApplication or reads
live window metadata. Exit status zero means that PID filtering, ordering,
normal-window counts, missing titles, empty titles, and malformed-row rejection
passed the in-memory fixtures. This check does not validate live Core Graphics
visibility or privacy behavior.
