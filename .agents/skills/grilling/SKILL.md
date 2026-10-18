---
name: grilling
description: Interview the user relentlessly about a plan or design. Use when the user wants to stress-test a plan before building, or uses any 'grill' trigger phrases.
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing. Asking multiple questions at once is bewildering.

If a question can be answered by exploring the codebase, explore it using **`skills/code-search/SKILL.md`** priority: (1) semantic MCP, (2) Grep/Glob/Read — then ask the human only if still unclear.

When composed via **`grill-with-docs`**, every resolved answer is written to Spec Kit
(`/speckit.clarify`, `/speckit.plan`, or `/speckit.specify`) immediately — see
`skills/grill-with-docs/SKILL.md`.