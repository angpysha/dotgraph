---
name: aot-compat-check
description: Publish Native AOT and check for trim/reflection warnings (IL2xxx/IL3xxx). Use when Native AOT mode is enabled.
---

# AOT Compat Check

```bash
scripts/publish-aot.sh 2>&1 | tee /tmp/aot-build.log
grep -E 'IL2[0-9]{3}|IL3[0-9]{3}|warning' /tmp/aot-build.log || true
```

Resolve all trim warnings before production handoff. See [docs/dotnet-code-style.mdc](../../../docs/dotnet-code-style.mdc) §6.
