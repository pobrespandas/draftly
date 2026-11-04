# Keep native text results out of the operation journal

Direct native reads and conversions can return private text that the person did
not ask Draftly to save. Keep that text in memory and persist only completion
with `resultAvailable: false` and `text: null`; recovery must not repeat the
operation to reconstruct its old result. Boolean delivery results can remain in
the journal. This trades durable text recovery for a smaller persistent data
scope while preserving request identity and the record of completed effects.
