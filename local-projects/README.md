# Local project configs

Copies of the machine-local `.nvim.lua` files (exrc) of projects, so every machine gets the same setup.

| File here | Lives at (in the project) |
| --- | --- |
| `supernova-env-dev.nvim.lua` | `supernova-env-dev/vendor/.nvim.lua` |

On a new machine: copy the file to its place (rename to `.nvim.lua`), adjust the root path at the top if the project lives elsewhere, then open nvim there and `:trust` it.

This repo is the synced copy. Whenever a project's `.nvim.lua` changes, copy it back here and commit and push in the same turn.
