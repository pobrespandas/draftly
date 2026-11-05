# Keep private native results out of the operation journal

Native reads, capture and automation can return private content that the person
did not ask Draftly to save. Keep each private result in memory and persist only
completion with `resultAvailable: false` and a null payload; recovery must not
repeat the operation to reconstruct its old result. Boolean delivery results
can remain in the journal. This trades durable content recovery for a smaller
persistent data scope while preserving request identity and completed effects.
