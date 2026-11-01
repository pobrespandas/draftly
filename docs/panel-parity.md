# Panel visibility review

## Native comparison — 1 November 2026

Compared Drafts 54.1.2 with the isolated Draftly Settings QA build. Used the
toolbar controls in both apps. The neutral draft text stayed unchanged.

| Operation | Drafts | Draftly QA |
| --- | --- | --- |
| Close the draft list while filters are open | Hides list and filters | Same |
| Reopen the draft list | Opens the list without filters | Same |
| Open filters while the list is hidden | Opens filters and list | Same |
| Close filters | Keeps the list open | Same |
| Close Actions | Keeps the left panels; expands the editor | Same |
| Reopen Actions | Restores its prior width | Same |

The accessibility splitter readings returned to their initial values after
each cycle. With all panels open, Drafts reported 239.5, 280, and 300 points.
QA reported 239.5, 280, and 452 points. The last reading is the editor width,
not the Actions width. The QA window was 152 points wider. Closing Actions
increased the editor reading by 261 points in both apps. Reopening Actions
reversed that change. Closing both left panels increased the editor reading
by 520.5 points in both apps.

When only filters were closed, the list reading was 280.5 points in both
apps. Opening filters restored 239.5 and 280. These half-point differences
occur in both native layouts. They do not show accumulated width drift.

No panel implementation change was needed for these tested transitions.

## Automated evidence

The existing `LibrarySplitViewTests` suite passed all 15 discovered tests.
The test runner verified the complete machine-readable report. The tests
cover controller identity, stored panel widths, expansion targets, custom
widths, narrow windows, recovery after window growth, and window title stability.

Command:

```sh
python3 scripts/run-swift-tests.py --diagnostic-suite LibrarySplitViewTests --output-dir /private/tmp/draftly-panel-review-20261101
```

## Limits

The native checks verify the settled layouts. They do not measure animation
duration or easing frame by frame. The headless tests do not establish visual
animation parity. The current code uses a 0.2-second ease-in/ease-out animation
and respects Reduce Motion. The matching reference timing remains unmeasured.

A native drag attempt returned `noWindowsAvailable`. Custom width retention
is covered by the automated tests, but this review did not complete a matching
manual drag sequence in both apps. No drag result is claimed.
