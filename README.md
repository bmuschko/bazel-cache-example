# Bazel cache example

A minimal Bazel 9 project that shows how Bazel avoids re-running actions through its caching layers.

The build is a chain of three `genrule` actions (`//:names` -> `//:greetings` -> `//:report`).
Each one sleeps for 3 seconds, so a re-executed action is easy to spot in the wall time.

## Caching layers

| Layer | Where it lives | Survives |
|-------|----------------|----------|
| In-memory action graph | Bazel server (Skyframe) | Consecutive builds in the same server |
| Local action cache | `<output_base>/action_cache` on disk | `bazel shutdown` |
| Disk cache (`--disk_cache`) | `~/.cache/bazel-cache-example/disk-cache` | `bazel clean --expunge`, other workspaces, other CI jobs |

The disk cache is enabled through `--config=disk` in `.bazelrc`.

## Running the demo

Bazel is pinned in `.bazelversion` and resolved by [Bazelisk](https://github.com/bazelbuild/bazelisk).

```shell
./scripts/demo.sh
```

The script runs these scenarios and fails if Bazel's process summary does not match the expectation.

1. Cold build: all 3 actions execute.
2. Rebuild in the same server: nothing executes and no cache is consulted.
3. Rebuild after `bazel shutdown`: 3 action cache hits.
4. Rebuild after `bazel clean --expunge`: 3 disk cache hits.
5. Change `data/greeting.txt`: only the 2 dependent actions execute.
6. Revert the change: 2 disk cache hits.

## GitHub Actions

The workflow in `.github/workflows/cache-demo.yml` has two parts.

- `local-caches` runs the full demo on Linux and macOS.
- `populate-disk-cache` fills the disk cache and saves it with `actions/cache`. `reuse-disk-cache` then restores it on a fresh runner and asserts that every action is a disk cache hit.
