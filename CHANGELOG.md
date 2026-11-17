# Changelog

All notable changes to this app are documented here. Versions follow
[Semantic Versioning](https://semver.org/) and match the Git tags in this
repository.

## [0.4.0] - 2026-11-12

### Changed

- Separated site configuration (`config/site.yml`) from the shared app code,
  so administrators no longer edit tracked templates to deploy or update a
  site.

### Fixed

- Ignored inherited user site-packages so they cannot shadow a shared
  Blackfish installation.

## [0.3.0] - 2026-04-16

### Changed

- Bumped the default Blackfish version to `1.0.0a0`.
- Updated the default shared cache directory for the Princeton Della
  deployment.
- Updated README documentation.

### Fixed

- Used a conda-managed environment and upgraded `pip` for shared
  installations.

## [0.2.0] - 2026-01-17

### Changed

- Removed the runtime UI build step; installations now ship as a single
  per-user Blackfish installation.
- Used a compatible release specifier for the selected Blackfish version and
  pinned to the latest compatible patch.

## [0.1.0] - 2025-07-18

### Added

- Initial release: launches a shared Blackfish server on a single HPC
  compute node via Open OnDemand Batch Connect, with a form for selecting a
  shared installation, app home directory, and session duration.
