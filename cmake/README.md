# CMake consumer module

This directory contains the consumer-side module behind the top-level
[nam.cmake](../nam.cmake) entrypoint.

It is include-only.

`nam.cmake` is not a script-mode downloader. It keeps the `ExternalData`
build-graph model so the intended consumer flow is a normal configure plus
build.

## Consumer usage

The public entrypoint is:

- `nam_add_channel_target(...)`

### Minimal usage

```cmake
include("${asset_manifests_repo}/nam.cmake")

nam_add_channel_target(
    TARGET media
)
```

Building target `media` then:

- fetches all assets from the default `media` channel
- reuses the shared local object store
- materializes release assets as files under
  `${CMAKE_CURRENT_BINARY_DIR}/media`
- keeps `zip` payloads as `zip` files

### Explicit usage

```cmake
include("${asset_manifests_repo}/nam.cmake")

nam_add_channel_target(
    TARGET media
    CHANNEL media
    REPO Devsh-Graphics-Programming/Nabla-Asset-Manifests
    TAG media
    DESTINATION_ROOT "${CMAKE_CURRENT_BINARY_DIR}"
    NO_SYMLINKS
    ITEMS
        <asset-key-1>
        <asset-key-2>
)
```

## Default arguments

- `CHANNEL = media`
- `REPO = Devsh-Graphics-Programming/Nabla-Asset-Manifests`
- `TAG = media`
- `DESTINATION_ROOT = ${CMAKE_CURRENT_BINARY_DIR}`
- `ITEMS = <all asset keys in CHANNEL>`
- `CACHE_ROOT = <ENTRY>/nabla/assets`
- `SHOW_PROGRESS = ON`
- `NO_SYMLINKS = OFF`
- `VERBOSE = OFF`

`<ENTRY>` resolves per platform:

- Windows: `%LOCALAPPDATA%`
- Linux: `${XDG_CACHE_HOME}` or `~/.cache`

## Module option

- `NAM_USE_VENDORED_EXTERNALDATA = ON`

By default NAM loads its vendored copy of `ExternalData.cmake`.

Set `-DNAM_USE_VENDORED_EXTERNALDATA=OFF` to use the stock `ExternalData.cmake`
shipped with the host CMake instead.

## Source of truth

For input assets the source of truth is:

- the physical channel tree such as `media/`
- `.dvc` files created by `dvc add`

The module reads those `.dvc` files and derives:

- the logical relative path inside the channel
- the expected release asset name
- the content hash used by the shared `ExternalData` object store

Current publishing convention:

- standalone payloads are published as individual files
- bundle directories are published as `zip` archives with the directory basename
- the current backend is `github_release`

Consumer-side rule:

- every published release asset is treated as a file
- nothing is unpacked automatically
- if a consumer wants to open a `zip`, it does so at runtime

## ExternalData model

When `NAM_USE_VENDORED_EXTERNALDATA=ON`, NAM uses
`cmake/vendor/ExternalData-NAM.cmake`, which is a vendored copy of CMake 4.2
`ExternalData.cmake`.

The vendored copy exists for one reason:

- stock `ExternalData.cmake` copies objects into `ExternalData_BINARY_ROOT` on
  Windows

That behavior creates a full build-local copy before the file reaches the final
consumer destination tree.

The NAM patch is intentionally small:

- it adds `ExternalData_LINK_MODE = auto|symlink|hardlink|copy`
- it lets NAM call the vendored build-time script directly per asset
- on the vendored path those modes are applied directly from the shared object
  store into the final destination tree

This keeps the shared object store model while avoiding an unnecessary physical
copy when the host supports lightweight links.

Once upstream CMake gains equivalent Windows behavior the default can be flipped
back by changing `NAM_USE_VENDORED_EXTERNALDATA` without changing consumer call
sites.

When `NAM_USE_VENDORED_EXTERNALDATA=OFF`, NAM falls back to the stock public
`ExternalData` flow:

- `ExternalData_Expand_Arguments`
- `ExternalData_Add_Target`
- `ExternalData_CUSTOM_SCRIPT_<key>`

The resulting model is:

- one shared local object store per user
- content-addressed objects under `.../objects/SHA256/<hash>`
- generated `.sha256` references under `${CMAKE_CURRENT_BINARY_DIR}/.nam/<target>/refs/<channel>/...`
- vendored-path metadata under `${CMAKE_CURRENT_BINARY_DIR}/.nam/<target>/file_stamps` and
  `${CMAKE_CURRENT_BINARY_DIR}/.nam/<target>/hash_records`
- direct final outputs under `${DESTINATION_ROOT}/${CHANNEL}/...` when the
  vendored module is enabled
- a stock-module fallback path under `${CMAKE_CURRENT_BINARY_DIR}/.nam/<target>/assets`
  only when `NAM_USE_VENDORED_EXTERNALDATA=OFF`
- normal build targets for consumers

During configure the module probes the current host once and selects the
lightest supported file materialization mode.

Current detection order is:

- Windows: `hardlink`, then `symlink`, then `copy`
- non-Windows: `symlink`, then `hardlink`, then `copy`

At build time:

- the vendored path fetches missing objects into the shared object store and
  materializes final files directly from that store
- on the default vendored path every release asset is exposed from the object
  store directly into the final destination root using the configured mode
- on the stock fallback path NAM keeps the older `.nam/<target>/assets` staging
  step and then materializes into the destination root

Passing `NO_SYMLINKS` forces copy materialization even when the host supports
lightweight links.

Explicit `symlink` mode on Windows still requires host symlink privilege.

## Logging

By default the module prints only:

- one short configure summary
- the normal build-time fetch/materialization output

## Smoke consumer

The repository also includes a minimal smoke consumer under `smoke/`.

Its local options are:

- `NAM_SMOKE_LINK_MODE = auto|symlink|hardlink|copy`
- `NAM_SMOKE_CACHE_ROOT = <path>`
- `NAM_SMOKE_NO_SYMLINKS = ON|OFF`

Those options are for smoke verification only. They are not part of the public
consumer module API.

The GitHub Actions workflow under `.github/workflows/smoke.yml` uses that smoke
consumer to verify:

- Windows and Linux runners
- explicit `symlink`, `hardlink`, and `copy` modes
- shared cache reuse via `${{ github.workspace }}/.nam-cache`
- post-build size and materialization statistics

Typical local smoke runs are:

```powershell
cmake -S smoke -B smoke/build
cmake --build smoke/build --config Debug --target media -- /m:1
```

```bash
cmake -S smoke -B smoke/build
cmake --build smoke/build --target media -- -j1
```

Forced copy mode:

```powershell
cmake -S smoke -B smoke/build -DNAM_SMOKE_NO_SYMLINKS=ON
cmake --build smoke/build --config Debug --target media -- /m:1
```

```bash
cmake -S smoke -B smoke/build -DNAM_SMOKE_NO_SYMLINKS=ON
cmake --build smoke/build --target media -- -j1
```

Explicit smoke-only mode overrides:

```powershell
cmake -S smoke -B smoke/build -DNAM_SMOKE_LINK_MODE=symlink
cmake -S smoke -B smoke/build -DNAM_SMOKE_LINK_MODE=hardlink
cmake -S smoke -B smoke/build -DNAM_SMOKE_LINK_MODE=copy
```

The smoke verification script then reports:

- per-tree materialization counts
- logical size of the materialized tree
- estimated extra disk cost of the chosen mode
- valid zip payload counts and generic largest-file stats

## Maintainer flow

Maintainers do not maintain a separate consumer catalog.

The maintainer-facing flow is only:

1. update the physical tree under `media/`
2. run `dvc add` on the changed standalone file or bundle directory
3. commit the updated `.dvc` metadata to Git
4. publish the matching payloads to the backend release channel
