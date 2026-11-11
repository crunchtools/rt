# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.3] - 2026-11-11

### Changed

- Builds go through the constitution container-release workflow: one build per
  change, the pushed digest is gated by `tests/test-image.sh --all`, and the
  merge promotes that digest to `:main` without a rebuild. `:latest` and the
  version tags move only on a `v*` tag. GHCR is dropped; Quay.io is the only
  registry. Moved to constitution v1.39.1.

- Added `.specify/memory/constitution.md` as a v1.18.0 manifest: it holds
  only what is specific to this repo; fleet and profile rules apply by
  reference.
- Constitution validation is pinned to the inherited release via
  `.github/workflows/constitution.yml`.
- Dependabot auto-merges GitHub Actions minor and patch updates.

## [1.0.2] - 2026-09-20

### Fixed
- Dual-push CI wiring reached this repo after v1.0.1 shipped; cutting the next
  patch so the release actually lands in both registries.
