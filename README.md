# Blackfish for Open OnDemand

## Overview

Blackfish for Open OnDemand is an Open OnDemand Batch Connect app that launches
a per-user [Blackfish](https://github.com/princeton-ddss/blackfish) AI
model-serving server, from a shared installation, as an interactive web
session directly on a login or
visualization node (the Open OnDemand cluster target for this app), not as a
Slurm batch job on a compute node. It is designed for researchers who need to
run AI models through Blackfish without installing or managing it themselves.
Blackfish itself submits model-serving jobs to compute nodes via Slurm and
forwards their ports from there, which is why its own server must run on a
login/visualization node rather than a compute node.

Users choose a site-provisioned Blackfish version, an application home
directory, and a session duration. Sites configure their cluster, shared
cache, installations, modules, and optional duration limits without editing
application code.

- Upstream project: [Blackfish](https://github.com/princeton-ddss/blackfish)
  ([Admin Guide](https://princeton-ddss.github.io/blackfish/latest/admin/architecture/))

## Features

- Launches a per-user Blackfish server, from a shared installation, via Open
  OnDemand Batch Connect
- Supports multiple shared Blackfish versions per site, selectable on the
  launch form
- Module-based or standalone executable installations
- Configurable session duration, with an optional site-enforced maximum
- Per-user application home directory, with automatic Slurm profile setup on
  first launch and preservation of existing profiles
- Timestamped launch-progress feedback in the session card

## Requirements

### Login/Visualization Node Software

- A shared [`blackfish-ai`](https://pypi.org/project/blackfish-ai/)
  installation (virtualenv executable or module-provided), provisioned by the
  site administrator; see [Installation](#installation) below
- Bash and `curl`
- Python 3 with its standard library (for first-time profile setup)
- Environment Modules or Lmod, only if a configured Blackfish version loads
  modules

### Open OnDemand

- Slurm (automatic profile setup currently creates a Slurm profile)
- Standard Open OnDemand Batch Connect (`role: batch_connect`); no OnDemand
  4.0+ automatic form fields are used

## Installation

### 1. Clone the repository

```bash
cd /var/www/ood/apps/sys
git clone https://github.com/princeton-ddss/blackfish-ondemand.git
cd blackfish-ondemand

# Pin to a release (recommended)
git checkout v0.4.0
```

### 2. Provision shared Blackfish installations

Administrators must provision each Blackfish version in a shared location.
For example, with a compatible Python available:

```bash
install_dir=/shared/blackfish/envs/1.0.0
umask 022
test ! -e "$install_dir" || exit 1
python3.12 -m venv "$install_dir"
"$install_dir/bin/python" -m pip install 'blackfish-ai==1.0.0'
PYTHONNOUSERSITE=1 "$install_dir/bin/blackfish" version
```

The shared path should be writable only by administrators and
readable/executable by app users. Virtual environment entry points contain
absolute paths, so create environments directly in the shared directory
(do not copy or move an environment). Install each new version in a separate
directory, e.g. `/shared/blackfish/envs/1.0.1`. Module-provided installations
are also supported.

Beyond this OOD-specific setup, administrators should also follow the
recommended steps to provide shared Blackfish resources (models, images,
etc.); see the upstream
[Admin Guide](https://princeton-ddss.github.io/blackfish/latest/admin/architecture/).

### 3. Configure for your site

Create an explicit site configuration:

```bash
cp config/site.example.yml config/site.yml
```

Edit `config/site.yml` for your institution (this file is Git-ignored). The
example contains placeholder paths and is never loaded automatically.
Alternatively, set `BLACKFISH_OOD_CONFIG` in the dashboard's environment to an
absolute YAML path, such as
`/etc/ood/config/apps/blackfish-ondemand/site.yml`. An explicitly selected
file takes precedence over an auto-discovered `config/site.yml`.

Use **Help > Restart Web Server** after site configuration or form changes if
values remain stale (OnDemand may cache form configuration).

See [Configuration](#configuration) below, [docs/configuration.md](docs/configuration.md),
and the [Princeton Della](docs/deployments/princeton-della.md) example
deployment for details.

## Configuration

Unlike many Batch Connect apps, site-specific values are not edited directly
into `form.yml.erb` or `manifest.yml`. They live in one YAML file,
`config/site.yml` (or the path named by `BLACKFISH_OOD_CONFIG`), so
application code stays shared and unmodified across sites.

| Key | Description | Default |
| --- | --- | --- |
| `cluster` | Required Open OnDemand cluster ID already configured in OnDemand; this app targets one cluster per configuration. | none |
| `cache_dir` | Required absolute shared cache path, used for first-time profile creation. | none |
| `default` | Required version key, must be present in `versions`. | none |
| `versions.<version>.executable` | Absolute executable path, or `blackfish` when supplied by `modules`. | none |
| `versions.<version>.modules` | Optional list of module names to load before running. | `[]` |
| `duration_hours.default` | Optional positive integer default session length, in hours. | `1` |
| `duration_hours.max` | Optional integer maximum session length, in hours; omit for no app-level limit. | none |

See [docs/configuration.md](docs/configuration.md) for the full schema,
file-selection order, and staging behavior.

## Known Limitations

- Each site must provision its own shared installations and `config/site.yml`;
  the committed examples are not active deployments.
- See the [FAQs](#faqs) below for home-directory reuse across versions and
  running multiple simultaneous instances.
- The launcher creates a `Default` Slurm profile only when no profiles exist;
  existing profiles, including earlier `ondemand` entries, are preserved
  as-is and not renamed or added to.
- Launch feedback uses the standard Open OnDemand info/completed templates
  and updates on refresh; it is not a continuously streamed log.
- Local tests use fake executables and do not establish site-specific
  properties such as Slurm submission, hostname/proxy routing, or shared
  cache permissions; see [REVIEW.md](REVIEW.md) for the full validation
  checklist.

## Development

### Testing

Developers can test the application locally by running:

```bash
ruby test/run.rb
```

Tests use temporary, neutral deployments and fake executables. They need
Ruby, Minitest, Bash, and Python 3; no `site.yml`, cluster, shared
installation, or network access is required. They cover configuration
selection and validation, staging snapshots, both executable/module forms,
profile preservation, failure handling, readiness, and escaped timestamped
feedback.

## FAQs

**Can I reuse a home directory across Blackfish versions?**

Blackfish applies database migrations at startup but does not enforce an
explicit downgrade guard. Earlier versions may not work with a home
initialized or upgraded by a newer version. Use separate homes for
incompatible Blackfish versions.

**Can a user run multiple instances of the app simultaneously?**

Yes, but they must use a separate home directory for each simultaneous
instance. Instances sharing a home also share database state and an
authentication-token file, which can cause conflicting initialization and CLI
authentication problems.

**I modified the site/form configuration, but I don't see any changes.**

OnDemand may cache form configuration: use **Help > Restart Web Server**
after site configuration or form changes if values remain stale.
