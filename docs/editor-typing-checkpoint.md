# Editor typing checkpoint

This checkpoint preserves marked text during syntax styling and view updates.
The user confirmed that accented input works in the new local process.

The styler reuses regular expressions and the link detector. It computes syntax
and task style ranges once per pass. It still styles the full document.

Validation: 20 tests passed across ThemeRenderingTests, EditorAutoMatchTests,
and EditorTypingPerformanceTests. The last Debug measurement used 130,500 UTF-16
units and five samples. Median change processing took 87.95 ms for committed
text and 0.01 ms for marked text. This is not end-to-end display latency.
The benchmark excludes the real save callback, syntax definition and theme.
It does not prove a general typing performance improvement.

Next: profile analysis, attribute application and layout separately. Evaluate
incremental styling before adding Neon or Tree-sitter. Keep syntax compatibility,
composition, selection and Undo behavior under test.

This checkout is far behind origin/main. Integrate the editor commits on the
current main branch and repeat validation before a release. Do not merge this
whole branch without reviewing its unrelated website history.
