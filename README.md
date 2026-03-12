<div align="center">
   <img alt="Click to see the source" height="200" src="nabla-glow.svg" width="200" />
</div>

<p align="center">
  <a href="https://github.com/Devsh-Graphics-Programming/Nabla-Asset-Manifests/actions/workflows/smoke.yml">
    <img src="https://github.com/Devsh-Graphics-Programming/Nabla-Asset-Manifests/actions/workflows/smoke.yml/badge.svg" alt="Smoke Status" /></a>
  <a href="https://opensource.org/licenses/Apache-2.0">
    <img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="License: Apache 2.0" /></a>
  <a href="https://discord.gg/krsBcABm7u">
    <img src="https://img.shields.io/discord/308323056592486420?label=discord&logo=discord&logoColor=white&color=7289DA" alt="Join our Discord" /></a>
</p>

# Nabla Asset Manifests

## Introduction

This repository is meant to hold lightweight metadata for shared Nabla assets and CI references without forcing large binary payloads into normal Git history.

The current Nabla examples layout at:

- `https://github.com/Devsh-Graphics-Programming/Nabla-Example-And-Tests-Media`

looks deceptively harmless because it is "just for examples", but it is already enough to create real operational problems. This is not a theoretical warning. The pattern is already known in practice to slow normal workflows down, make asset maintenance heavier than it should be, work against setups such as Git worktrees, and couple ordinary source-control operations to large binary payload churn. That is a design mistake for asset distribution, even in an examples-only repository, and this pattern should be avoided in other projects as well.

The core argument is simple. Source control should keep code and small reviewable metadata. Heavy payloads should stay outside normal Git history.

## Model

The intended direction is:
- manifests and references in Git
- payloads outside Git history
- backend-agnostic consumers
- one shared local object store per user
- normal local files materialized into build trees for examples and tests
- shared blob reuse across many build directories, many checkouts, and even many independent repositories

At a high level this follows the same pattern used by mature package and artifact ecosystems:
- manifest plus URL plus checksum in `winget`
- formula or cask plus bottle URL plus checksum in `Homebrew`
- `binaryTarget(url:, checksum:)` in `SwiftPM`
- content-addressed external test data in `CMake ExternalData`, used by projects such as `VTK`

## Evidence

### Git History Pressure

[`git-fat`](https://github.com/jedbrown/git-fat):

> Checking large binary files into a source repository (Git or otherwise) is a bad idea because repository size quickly becomes unreasonable. Even if the instantaneous working tree stays manageable, preserving repository integrity requires all binary files in the entire project history, which given the typically poor compression of binary diffs, implies that the repository size will become impractically large. Some people recommend checking binaries into different repositories or even not versioning them at all, but these are not satisfying solutions for most workflows.

[GitHub repository limits](https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits):

> Large repositories can slow down fetch operations and increase clone times for developers and CI.

or from the same page:

> Store programmatically generated files outside of Git, such as in object storage.

## Why not Git LFS as the primary model

Git LFS is better than checking large blobs directly into normal Git history, but it is still not the model we want to optimize around here.

The strongest reasons are:
- it stays Git-centric instead of backend-agnostic
- it couples asset transport to hosting policy and billing
- it complicates long-term migration and reversibility

[Gregory Szorc](https://gregoryszorc.com/resume.pdf), former technical steward of the Firefox build system at Mozilla and maintainer of Firefox version control infrastructure. Quote source: [Why you shouldn't use Git LFS](https://gregoryszorc.com/blog/2021/05/12/why-you-shouldn%27t-use-git-lfs/):

> If you adopt LFS today, you are committing to a) running an LFS server forever b) incurring a history rewrite in the future in order to remove LFS from your repo, or c) ceasing to provide an LFS server and locking out people from using older Git commits.

> So adoption of Git LFS is a one way door that can't be easily reversed.

[`DVC`](https://github.com/iterative/dvc):

> Store them in your cloud storage but keep their version info in your Git repo.

Operational failure modes are documented very explicitly:

from [GitHub LFS billing and quota behavior](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-storage-and-bandwidth-usage):

> Git LFS support is disabled on your account until the next month.

or from [GitHub LFS objects in archives](https://docs.github.com/github/administering-a-repository/managing-repository-settings/managing-git-lfs-objects-in-archives-of-your-repository):

> Every download of those archives will count towards bandwidth usage.

or from [GitLab storage quota behavior](https://docs.gitlab.com/user/storage_usage_quotas/):

> When a project’s repository and LFS exceed the limit, the project is set to a read-only state and some actions become restricted.

or from [Bitbucket Cloud current limitations for Git LFS](https://support.atlassian.com/bitbucket-cloud/docs/current-limitations-for-git-lfs-with-bitbucket/):

> Once any user pushes the first LFS file to the repo, then transferring of that repo is disabled.

## Why `CMake ExternalData`

[VTK](https://docs.vtk.org/en/latest/api/cmake/vtkModuleTesting.html):

> VTK uses the ExternalData CMake module to handle the data management for its test suite. Test data is only downloaded when a test which requires it is enabled and it is cached so that every build does not need to redownload the same data.

[CMake ExternalData latest documentation](https://cmake.org/cmake/help/latest/module/ExternalData.html):

> manage data files stored outside source tree

From the same documentation:

> Fetch them at build time from arbitrary local and remote content-addressed locations.

[Kitware on `CMake ExternalData`](https://www.kitware.com/cmake-externaldata-using-large-files-with-distributed-version-control/):

> The separate repository requires extra work for users to checkout and developers to maintain. Furthermore, the data repository still grows large over time.

This is the exact consumer model we want:
- a shared local object store
- reuse across many build directories and worktrees
- reuse across many independent repositories too
- normal local files materialized into build trees via symlinks, hardlinks, or copies
- no requirement for consumers to know which remote backend served the blob

## Backends

The first backend is `GitHub Release assets`.

[GitHub release assets documentation](https://docs.github.com/articles/distributing-large-binaries):

> We don't limit the total size of the binary files in the release or the bandwidth used to deliver them. However, each individual file must be smaller than 2 GiB.

The backend itself does not matter:
- it can be `GitHub Release assets`
- it can be `S3`
- it can be a custom object store
- it can be an internal mirror or a static file server

Multiple backends can coexist with ordered fallback. If we later replace `GitHub Release assets` with a different backend, consumers do not have to notice. They continue to resolve the same manifests into the same logical local files.

Release publishing policy in this prototype is intentionally simple:
- standalone assets are published as individual files
- bundles are published as zip archives

## Target layout

<details>
<summary>Click to expand</summary>

```text
media/
  assets/
    mesh/
      standalone/
        obj/
        ply/
        stl/
      bundles/
        obj/
    image/
      standalone/
        exr/
        png/
        jpg/
        jpeg/
        tga/
        dds/
        ktx/
    photometry/
      ies/
    scene/
      mitsuba/
        xml/
        serialized/
        bundles/
    archive/
      zip/
    data/
      text/
      json/

references/
  perf/
    meshloaders/

licenses/
```

</details>

## Current scope

This is only the starting point.

The repository is intentionally designed so that the rest of the current Nabla `media` tree can be migrated here later under the same model.
