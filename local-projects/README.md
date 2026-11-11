# Local project configs

Copies of the machine-local `.nvim.lua` files (exrc) of projects, so every machine gets the same setup.

| File here | Lives at (in the project) |
| --- | --- |
| `supernova-env-dev.nvim.lua` | `supernova-env-dev/vendor/.nvim.lua` |

On a new machine: copy the file to its place (rename to `.nvim.lua`), adjust the root path at the top if the project lives elsewhere, then open nvim there and `:trust` it.

This repo is the synced copy. Whenever a project's `.nvim.lua` changes, copy it back here and commit and push in the same turn.

## supernova-digiexpress-test-dbs.sh

Creates the databases the parallel test workers use (`digiexpress_N`, `digiexpress_log_N`, a clone of `digiexpress_1` /
`digiexpress_log_1`). Copy it into the mysql container and run it with the numbers wanted:

```
docker cp supernova-digiexpress-test-dbs.sh supernova-env-dev-mysql-1:/tmp/clonedb.sh
docker exec supernova-env-dev-mysql-1 sh /tmp/clonedb.sh 2 3 4 5 6 7 8 9 10 11 12 13 14 15
```

Needed once per machine (and again after the mysql volume is rebuilt). `supernova-env-dev.nvim.lua` uses worker slots 1..15.
