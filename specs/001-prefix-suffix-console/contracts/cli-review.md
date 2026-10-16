# Contract: Console review

Commands stay `dotgraph update` and `dotgraph sync`. Flags stay `--interactive`, `--dry-run`, and `--force` (update only).

Renderer: Spectre.Console markup only. Words carry the meaning when color is stripped (`NO_COLOR`, redirected stdout, or a terminal without ANSI).

## Change line

Every preview, diff row, and review line uses the same words and colors.

| Situation | Word | Color |
|---|---|---|
| Major | MAJOR | red |
| Minor | MINOR | yellow |
| Patch | PATCH | green |
| Suffix only | SUFFIX | grey |
| Failure | Error | red |
| Earlier release or other warning | Warning | yellow |
| Secondary detail | plain grey text | grey |

Prefix and suffix are always both shown. Absent suffix is the word `none`.

```text
prefix 1.2.0 → 1.2.1    suffix none → none    PATCH
prefix 1.0.0 → 1.0.0    suffix beta → rc.1    SUFFIX
```

## `update` and `sync` preview

Before any write, the proposal table or diff lists, for each affected package: current prefix, current suffix or `none`, proposed prefix, proposed suffix or `none`, the change word, and the reason.

`--dry-run` prints that preview and does not change project files or `.dotgraph.json`. Exit code 0.

## Interactive review

Used by `update --interactive` and `sync --interactive`.

1. Named root changes, each with prefix, suffix, and change word.
2. One screen per follow-up package, with `Package N of M`, current prefix, current suffix, proposed prefix, proposed suffix, and one reason line.
3. Choices, Accept focused first:
   - Accept proposed
   - Enter a version
   - Leave unchanged
4. A typed version must be `MAJOR.MINOR.PATCH` or `MAJOR.MINOR.PATCH-suffix`. Otherwise the console prints `Invalid version. Example: 1.2.3 or 1.2.3-beta.1` and asks again on the same package.
5. A typed version equal to the current one is Leave unchanged.
6. A typed or explicit version that is earlier than the current one prints Warning with both versions. Interactive mode asks for confirmation. `--force` accepts it without that extra question. Non-interactive `update` without `--force` exits 1 and writes nothing.
7. Summary groups "Will change" (from → to, and whether it was explicit, accepted, or typed) and "Left unchanged".
8. One yes/no question applies the "Will change" set. No writes before yes.
9. If "Will change" is empty, print `Nothing will be written.` and do not ask. Exit 0.
10. Answering no prints that nothing was written. Exit 0. Project files and `.dotgraph.json` stay as they were.

`sync` still writes only the accepted follow-up bumps. Roots were already edited by the developer. `update` writes the explicit roots that differ, plus accepted or typed follow-ups.

## Exit codes

| Result | Code |
|---|---|
| Applied, or nothing to do, or user declined | 0 |
| Missing `.dotgraph.json`, unknown package, invalid version argument, non-interactive downgrade without `--force`, write or save failure | 1 |

Unknown package: name it, suggest close names when any exist, write nothing.
Missing snapshot: tell the user to run `dotgraph init`, write nothing.
