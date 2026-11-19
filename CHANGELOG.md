# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Promote signs the image with the fleet cosign key (`sign: true`), because
  bootc hosts are moving to trust only signed `quay.io/crunchtools` images
  (crunchtools/rhel10-bootc-server#47). Needs the repo's `cosign-signing`
  environment to hold `COSIGN_PRIVATE_KEY` and `COSIGN_PASSWORD`.
- The container release runs constitution v1.51.0's `container-release.yml`
  (was v1.46.0) and grants it `issues: write`, so a failed scheduled rebuild
  opens an issue instead of only warning. A `v*` promote now also refuses an
  image whose `version` label names a different release of this repo; this
  image sets no `version` label of its own, so the check is inert here.

## [1.0.4] - 2026-11-13

### Security
- Rebuilt on ubi10-httpd with mod_http2 2.0.29-5.el10_3.1 (CVE-2026-119618).

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
