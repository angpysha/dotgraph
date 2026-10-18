## Post-tasks: optional grilling (risk-recommended)

After the `br` graph exists and `tasks.md` has been rendered, offer **optional** grilling
of the task plan (use the **grilling** / **grill-with-docs** skills).

### Always

Prompt: ask whether to grill the task breakdown (one question at a time, with a recommended
answer). Declining is allowed and MUST NOT fail the phase — note deferred risks.

### When to **recommend** grilling (risk)

If **either** is true:

1. The graph has a **parallel-ready batch** (`[P]` / multiple `br ready` peers), or
2. There are **cross-story** dependencies

Then emit an explicit risk warning, for example:

> **Risk:** Parallel marks and/or cross-story dependencies can hide false parallelism or
> missed blockers. **Grilling is recommended** before implement.

Still skippable if the user declines.

### On accept

1. Apply resolved answers to **`br` first** (title/description/deps/labels)
2. Re-run `Render-TasksFromBr.ps1` so `tasks.md` matches
3. Never leave markdown ahead of `br`

### On decline

Record deferred risks in the session/notes section of the projection if useful; continue.
