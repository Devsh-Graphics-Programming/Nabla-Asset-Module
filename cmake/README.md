# CMake consumer module

This directory contains the consumer-side module behind the top-level
[nam.cmake](../nam.cmake)
entrypoint.

It is meant to be used in two ways:

- include [nam.cmake](../nam.cmake) from another CMake project
- execute [nam.cmake](../nam.cmake) through `cmake -P`

The current implementation resolves consumer requests through `CMake ExternalData`.

## Consumer usage

### Include mode with defaults

```cmake
include("${asset_manifests_repo}/nam.cmake")

nam_fetch_channel()
nam_fetch_and_materialize_channel(
    DESTINATION_ROOT "${CMAKE_CURRENT_BINARY_DIR}/media"
)
```

That uses the default channel, repository, tag and cache root.

### Include mode with explicit arguments

```cmake
include("${asset_manifests_repo}/nam.cmake")

nam_fetch_and_materialize_channel(
    CHANNEL "media"
    REPO "Devsh-Graphics-Programming/Nabla-Asset-Manifests"
    TAG "media"
    DESTINATION_ROOT "${CMAKE_CURRENT_BINARY_DIR}/media"
    ITEMS
        Stanford_Bunny.stl
        yellowflower.zip
)
```

### Script mode with defaults

```powershell
cmake -P nam.cmake nam_fetch_channel
cmake -P nam.cmake nam_fetch_and_materialize_channel DESTINATION_ROOT ./nabla_media
```

### Script mode with explicit arguments

```powershell
cmake -P nam.cmake nam_fetch_channel CHANNEL media ITEMS Stanford_Bunny.stl
cmake -P nam.cmake nam_materialize_channel CHANNEL media ITEMS Stanford_Bunny.stl DESTINATION_ROOT ./nabla_media
cmake -P nam.cmake nam_fetch_and_materialize_channel CHANNEL media DESTINATION_ROOT ./nabla_media
cmake -P nam.cmake nam_fetch_channel VERBOSE CHANNEL media ITEMS Stanford_Bunny.stl
```

The first positional argument is always the CMake function name.

- `nam_fetch_channel`
- `nam_materialize_channel`
- `nam_fetch_and_materialize_channel`

All remaining arguments are passed through `1:1` to that function.

For asset selectors, `ITEMS` can contain either:

- a logical relative path under the channel root
- or the published release asset basename

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
- backend-specific resolution is isolated inside the module so the public
  consumer API does not have to change when the storage backend changes later
- once the backend digest is known, the payload is fetched into the shared
  `ExternalData` object store and then materialized from there

## Default arguments

The current defaults are:

- `CHANNEL = media`
- `REPO = Devsh-Graphics-Programming/Nabla-Asset-Manifests`
- `TAG = media`
- `CACHE_ROOT = <ENTRY>/nabla/assets`

`<ENTRY>` resolves per platform:

- Windows: `%LOCALAPPDATA%`
- Linux: `${XDG_CACHE_HOME}` or `~/.cache`

If `DESTINATION_ROOT` is not provided:

- in normal CMake configure mode it defaults to `${CMAKE_BINARY_DIR}/nabla-assets-materialized`
- in script mode it defaults to `<repo>/_materialized`

Materialization is separate from fetch:

- `fetch` populates the shared `ExternalData` object store
- `materialize` creates consumer-visible local files or extracted bundle trees

Incremental behavior is intentionally cheap:

- the release metadata is queried once per CMake process
- the shared object store is content-addressed through `ExternalData`
- once an object is already present in that store the next fetch reuses it
  without re-downloading

Logging behavior is intentionally split into two levels:

- by default the module prints only a short start line and a final summary
- with `VERBOSE` it also prints per-asset resolution, cache-hit and
  materialization details
- download progress is shown whenever an actual download happens

## Design constraints

- maintainers only maintain the repository through the physical layout plus
  `git` and `DVC`
- consumer-side CMake reads `.dvc` files directly
- there is no separate hand-maintained asset catalog for CMake to consume

By default:

- standalone assets are materialized through symbolic links
- if symlinks are not available CMake falls back to copying
- bundle archives are extracted into their logical destination directory

## Maintainer flow

Maintainers do not maintain a separate consumer catalog.

The maintainer-facing flow is only:

1. update the physical tree under `media/`
2. run `dvc add` on the changed standalone file or bundle directory
3. commit the updated `.dvc` metadata to Git
4. publish the matching payloads to the backend release channel

The consumer module then reads those `.dvc` files directly and keeps using the
same public API.
