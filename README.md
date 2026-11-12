# Blackfish for Open OnDemand

A reusable Open OnDemand app for launching a shared `blackfish-ai` installation.
Users choose a configured version, an application home, and a duration. Sites
configure their cluster, cache, installations, modules, and optional duration
limits without editing application code.

## Deployment

### Requirements

The runtime needs Bash, curl, Python 3 with its standard library, and a selected
Blackfish installation. When modules are configured, the app
uses an existing module function or `/etc/profile.d/modules.sh`, purges inherited
modules, and loads the configured list. Sites with another module initialization
method should make the module function available through their OnDemand job setup.

For home directories without existing profiles, automatic setup currently creates
a default Slurm profile. Existing profiles and their default selection are preserved.

### Configuration

> [!NOTE]
> Beyond the OOD-specific setup outlined here, administrators should also follow
> the recommended steps to provide shared resources for Blackfish (models, images,
> etc.). For details, see our [Admin Guide](https://princeton-ddss.github.io/blackfish/latest/admin/architecture/).

Clone this repository under your Open OnDemand dev app directory and create an
explicit site configuration:

```bash
cp config/site.example.yml config/site.yml
```

Edit `config/site.yml` for your institution (this file is Git-ignored). The example
contains placeholder paths and is never loaded automatically. Alternatively,
set `BLACKFISH_OOD_CONFIG` in the dashboard's environment to an absolute YAML path,
such as `/etc/ood/config/apps/blackfish-ondemand/site.yml`. An explicitly selected
file takes precedence over an auto-discovered `config/site.yml`.

See [Configuration](docs/configuration.md) and the [Princeton Della](docs/deployments/princeton-della.md) example deployment for details.

### Shared installations

Administrators must provision Blackfish versions in a shared location and list
each version in the site config. For example, with a compatible Python available:

```bash
install_dir=/shared/blackfish/envs/1.0.0
umask 022
test ! -e "$install_dir" || exit 1
python3.12 -m venv "$install_dir"
"$install_dir/bin/python" -m pip install 'blackfish-ai==1.0.0'
PYTHONNOUSERSITE=1 "$install_dir/bin/blackfish" version
```

The shared path should be writable only by administrators and readable/executable
by app users. Virtual environment entry points contain absolute paths, so create
environments in the shared directory (i.e., do not copy or move an environment).
Each new version should be installed in a separate directory, e.g.,
`/shared/blackfish/envs/1.0.1`.

Module-provided installations are also supported.

## Development

### Testing

Developers can test the application locally by running:

```bash
ruby test/run.rb
```

Tests use temporary, neutral deployments and fake executables. They need Ruby,
Minitest, Bash, and Python 3; no site.yml, cluster, shared installation, or network
access is required. They cover configuration selection and validation, staging
snapshots, both executable/module forms, profile preservation, failure handling,
readiness, and escaped timestamped feedback.

## FAQs

**Can I reuse a home directory across Blackfish versions?**

Blackfish applies database migrations at startup but does not enforce an explicit
downgrade guard. Earlier versions may not work with a home initialized or upgraded
by a newer version. Use separate homes for incompatible Blackfish versions.

**Can a user run multiple instances of the app simultaneously?**

Yes, but they must use a separate home directory for each simultaneous instance.
Instances sharing a home also share database state and an authentication-token file, which can cause conflicting initialization and CLI authentication problems.

**I modified the site/form configuration, but I don't see any changes.**

OnDemand may cache form configuration: use **Help > Restart Web Server** after
site configuration or form changes if values remain stale.
