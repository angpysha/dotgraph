## Git branch (branch-format preset)

When this project has the **branch-format** preset installed, the feature **git branch**
MUST be created via the always-on **branch-format** skill as `{type}/{ISO-week}-{slug}`
(e.g. `feature/33-speckit-branch-format`). Parameters come from context or the user.

This Spec Kit **feature directory** (`specs/NNN-slug`) remains independent of the git
branch name. Record the git branch in the Feature Branch field if useful; do not rename
the feature directory to match.
