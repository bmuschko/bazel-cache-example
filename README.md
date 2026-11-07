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

## Prerequisites

Install [Bazelisk](https://github.com/bazelbuild/bazelisk).
It reads `.bazelversion` and downloads the pinned Bazel version on first use.
The commands below call `bazelisk`. If Bazelisk is installed as `bazel`, use that name instead.

Watch the `INFO: N processes: ...` line near the end of each build's output.
On Linux the execution strategy is `linux-sandbox` or `processwrapper-sandbox` instead of `darwin-sandbox`.

Steps 1 through 4 build without the disk cache, and steps 5 through 8 build with it.

## Step 1: Cold build

Start from an empty output base and an empty disk cache.

```shell
bazelisk clean --expunge
rm -rf ~/.cache/bazel-cache-example/disk-cache
bazelisk build //:report
```

All 3 actions execute, which takes about 9 seconds.

```
INFO: 4 processes: 1 internal, 3 darwin-sandbox.
```

The output is written to the output base, which `bazel-bin` in the project root links to.

```shell
cat bazel-bin/report.txt
```

```
Greetings report
Hello, ALICE!
Hello, BOB!
Hello, CAROL!
```

## Step 2: Rebuild in the same server (in-memory)

```shell
bazelisk build //:report
```

The Bazel server still holds the action graph in memory and knows nothing changed.
No action is executed and no cache is checked.

```
INFO: 1 process: 1 internal.
```

## Step 3: Rebuild after a server restart (local action cache)

```shell
bazelisk shutdown
bazelisk build //:report
```

The in-memory state is gone, but the action cache in the output base was written to disk on shutdown.
Bazel checks each action against it and finds the outputs already in place.

```
INFO: 1 process: 3 action cache hit, 1 internal.
```

## Step 4: Rebuild after a full clean without the disk cache

```shell
bazelisk clean --expunge
bazelisk build //:report
```

The output base, including its action cache and all outputs, is deleted.
No cache is left, so all 3 actions execute again.

```
INFO: 4 processes: 1 internal, 3 darwin-sandbox.
```

## Step 5: Fill the disk cache

```shell
bazelisk clean --expunge
bazelisk build --config=disk //:report
```

The disk cache only receives results from actions that execute.
The output base is cleaned first, so the results of step 4 cannot be reused and all 3 actions execute and are stored in the disk cache.

```
INFO: 4 processes: 1 internal, 3 darwin-sandbox.
```

## Step 6: Rebuild after a full clean with the disk cache

```shell
bazelisk clean --expunge
bazelisk build --config=disk //:report
```

The disk cache lives outside the output base, so it survives the clean and every action result is fetched from it.

```
INFO: 4 processes: 3 disk cache hit, 1 internal.
```

## Step 7: Change one input

```shell
echo 'Howdy' > data/greeting.txt
bazelisk build --config=disk //:report
```

`//:names` does not depend on `data/greeting.txt`, so it is skipped through the in-memory graph.
Only `//:greetings` and `//:report` execute, and their new results are added to the disk cache.

```
INFO: 3 processes: 1 internal, 2 darwin-sandbox.
```

## Step 8: Revert the change

```shell
echo 'Hello' > data/greeting.txt
bazelisk build --config=disk //:report
```

Results from earlier builds are kept, not overwritten, so both actions are disk cache hits.

```
INFO: 3 processes: 2 disk cache hit, 1 internal.
```

## GitHub Actions

The workflow in `.github/workflows/cache-demo.yml` runs every step above as a separate workflow step.
After each build, `scripts/verify-build.sh` fails the step if the process summary does not match the expected counts.

- `local-caches` runs steps 1 through 8 on Linux and macOS.
- `populate-disk-cache` fills the disk cache and saves it with `actions/cache`. `reuse-disk-cache` then restores it on a fresh runner and asserts that every action is a disk cache hit.
