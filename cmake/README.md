# CMake consumer module

This directory contains the consumer-side module behind the top-level
[nam.cmake](../nam.cmake) entrypoint.

It is include-only.

`nam.cmake` is not a script-mode downloader. The public `ExternalData` API is
build-graph based so the intended consumer flow is a normal configure plus
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
- materializes standalone files and bundle directories under
  `${CMAKE_CURRENT_BINARY_DIR}/media`

### Explicit usage

```cmake
include("${asset_manifests_repo}/nam.cmake")

nam_add_channel_target(
    TARGET media
    CHANNEL media
    REPO Devsh-Graphics-Programming/Nabla-Asset-Manifests
    TAG media
    DESTINATION_ROOT "${CMAKE_CURRENT_BINARY_DIR}"
    ITEMS
        Stanford_Bunny.stl
        yellowflower.zip
)
```

## Default arguments

- `CHANNEL = media`
- `REPO = Devsh-Graphics-Programming/Nabla-Asset-Manifests`
- `TAG = media`
- `DESTINATION_ROOT = ${CMAKE_CURRENT_BINARY_DIR}`
- `CACHE_ROOT = <ENTRY>/nabla/assets`
- `SHOW_PROGRESS = ON`

`<ENTRY>` resolves per platform:

- Windows: `%LOCALAPPDATA%`
- Linux: `${XDG_CACHE_HOME}` or `~/.cache`

## Source of truth

For input assets the source of truth is:

- the physical channel tree such as `media/`
- `.dvc` files created by `dvc add`

The module reads those `.dvc` files and derives:

- the logical relative path inside the channel
- whether a payload is a standalone file or a bundle directory
- the expected release asset name
- the content hash used by the shared `ExternalData` object store

Current publishing convention:

- standalone payloads are published as individual files
- bundle directories are published as `zip` archives with the directory basename
- the current backend is `github_release`

## ExternalData model

The module uses only public `ExternalData` APIs:

- `ExternalData_Expand_Arguments`
- `ExternalData_Add_Target`
- `ExternalData_CUSTOM_SCRIPT_<key>`

It does not call private `_ExternalData_*` functions and it does not spawn
nested `cmake.exe` processes from the module itself.

The resulting model is:

- one shared local object store per user
- content-addressed objects under `.../objects/SHA256/<hash>`
- generated content links under `nam-data/<target>/` in the consumer source tree
- normal build targets for consumers
- archive extraction as an explicit build step for bundle payloads

At build time:

- `ExternalData` populates the shared object store
- standalone files are materialized to the destination root
- bundle archives are materialized and extracted to the destination root

## Logging

By default the module prints only:

- one short configure summary
- the normal build-time `ExternalData` output

## Maintainer flow

Maintainers do not maintain a separate consumer catalog.

The maintainer-facing flow is only:

1. update the physical tree under `media/`
2. run `dvc add` on the changed standalone file or bundle directory
3. commit the updated `.dvc` metadata to Git
4. publish the matching payloads to the backend release channel
