# Blackfish for Open OnDemand

A reusable Open OnDemand app for launching a shared Blackfish installation.
Users choose a configured version, an application home, and a duration. Sites
configure their cluster, cache, installations, modules, and optional duration
limits without editing application code.

## Configure a deployment

Clone this repository under your Open OnDemand dev app directory, then create an
explicit site configuration:

```bash
cp config/site.example.yml config/site.yml
```

Edit `config/site.yml` for your institution. It is ignored by Git. The example
contains placeholder paths and is never loaded automatically. Alternatively,
set `BLACKFISH_OOD_CONFIG` in the dashboard's environment to an absolute YAML path,
such as `/etc/ood/config/apps/blackfish-ondemand/site.yml`. An explicitly selected
file takes precedence; errors do not fall back to another file.

A missing site configuration produces a setup error. There is no implicit cluster,
shared cache, installation, or institutional default. The configured cluster ID
must already exist in Open OnDemand's cluster configuration. Scheduler connections,
hostname routing, and proxy configuration remain the site's OnDemand responsibility.

See [Configuration](docs/configuration.md) for the schema and deployment behavior.
The public [Princeton Della example](docs/deployments/princeton-della.md) documents
one deployment; it is not the active configuration of a clean checkout.

## Shared installations

An administrator provisions each exact Blackfish version once in its final shared
location and lists it in the site config. Sessions never create environments or
install or upgrade packages. For example, with a compatible Python available:

```bash
install_dir=/shared/blackfish/envs/1.0.0
umask 022
test ! -e "$install_dir" || exit 1
python3.12 -m venv "$install_dir"
"$install_dir/bin/python" -m pip install 'blackfish-ai==1.0.0'
PYTHONNOUSERSITE=1 "$install_dir/bin/blackfish" version
```

Choose a shared path accessible from every target node. Keep the installation
writable only by administrators and readable/executable by app users. Environment
entry points contain absolute paths, so create environments at their final paths.
Provision required container images separately in the shared cache. Install new
versions in separate directories and retain older installations until their queued
and running sessions have finished. Module-provided installations are also supported.

The runtime needs Bash, curl, Python 3 with its standard library, and the selected
Blackfish installation and its dependencies. When modules are configured, the app
uses an existing module function or `/etc/profile.d/modules.sh`, purges inherited
modules, and loads the configured list. Sites with another module initialization
method should make the module function available through their OnDemand job setup.

## User behavior

The form offers duration, configured Blackfish versions, and application home.
The generic home default is `~/.blackfish`; users may choose another absolute path.
Previously saved form values can retain `~/.blackfish-ondemand`. Data is not moved.

When any profiles exist, the launcher preserves them and their resolved default.
Only a home without profiles receives an initial profile named `Default`, using
`localhost`, the current user, the selected home, and the administrator's cache.
The bootstrap currently creates Slurm profiles; other scheduler integrations would
need corresponding Blackfish support. Existing profiles are not added to, renamed,
or replaced. The admin cache is checked only for first-time profile creation.
Users manage existing profiles in Blackfish or its CLI. Malformed configuration
stops startup instead of being overwritten.

Run one server per home. Use separate homes for incompatible Blackfish versions:
Blackfish migrates data and records its version without an explicit downgrade guard.

## Launch feedback

Active and completed session cards show up to 40 timestamped launch entries.
`launch-status.txt` retains the history; detailed Blackfish output is in
`output.log`, available through OnDemand's session-data link. The card displays
launcher progress, not raw Blackfish output. Blackfish itself can print startup
credentials in private job output; the launcher does not duplicate tokens or
turn on shell tracing.

The first failure is retained without a redundant wrapper error. Initial cache
failures identify the configured path. A connection is published only after HTTP
readiness, with early-exit detection and a roughly 120-second startup deadline.
The server binds all IPv4 interfaces while proxy URLs retain the node hostname.
The local readiness probe cannot verify connectivity from the OnDemand host.

Feedback updates with the session card/page rather than streaming continuously.
OnDemand may cache form configuration: use **Help > Restart Web Server** after
site configuration or form changes if values remain stale.

## Validation

```bash
ruby test/run.rb
```

Tests use temporary, neutral deployments and fake executables. They need Ruby,
Minitest, Bash, and Python 3; no site.yml, cluster, shared installation, or network
access is required. They cover configuration selection and validation, staging
snapshots, both executable/module forms, profile preservation, failure handling,
readiness, and escaped timestamped feedback.

There is no CI in this repository. Before deployment, rerun the local suite and
verify a dev session with a fresh home, an existing home, proxy authentication,
shared cache access, launch history, and deliberate configuration/setup failures.
[REVIEW.md](REVIEW.md) records existing findings and limitations.
