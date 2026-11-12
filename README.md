# Blackfish for Open OnDemand

The official Open OnDemand application for Blackfish-AI. It launches a Blackfish
server on a login node with minimal resources. Users authenticate and interact with
the server through the OOD proxy and Blackfish UI in their browser. Sessions use
administrator-managed shared installations.

## Shared installation setup

An administrator must provision the shared executable before deploying this
change. The path in `installations.yml` is a proposed location, not an existing
installation verified by this repository. Choose a durable shared filesystem
accessible from the dashboard and all `della` nodes. The installer must have
write access; ordinary app users need only read and execute access.

For the initially configured version, run once on Della as the installation owner:

```bash
module load anaconda3/2024.6
umask 022
install_dir=/scratch/gpfs/DDSS/.blackfish/envs/1.0.0
# Use a fresh destination. Do not replace an installation while sessions use it.
test ! -e "$install_dir" || exit 1
python -m venv "$install_dir"
"$install_dir/bin/python" -m pip install 'blackfish-ai==1.0.0'
PYTHONNOUSERSITE=1 "$install_dir/bin/blackfish" version
```

This creates one shared Python environment, rather than an environment per user.
Check that the module provides a Python version supported by the selected release
(Python 3.12 for current Blackfish). All parent directories must be traversable by
app users. Keep the installation and modulefiles writable only by administrators.
Provision container images separately in the shared cache. Installation paths are
embedded in Python entry points: create each environment at its final location.

For each additional release, install into a separate version directory and add
its exact package version and executable to `installations.yml`. Set `default` to
one of its version keys. Only configured versions appear in the launch form;
stale or forged version selections are rejected, and the launcher checks the
executable's reported version before initializing user data. Version choices are
snapshotted into staged sessions, so keep old installations available until their
queued and running sessions have ended.

## Moving to environment modules

The catalog already supports environment modules. Once a site module is available,
an entry can use the executable provided by that module:

```yaml
cache_dir: "/scratch/gpfs/DDSS/.blackfish"
default: "1.0.0"
versions:
  "1.0.0":
    executable: "blackfish"
    modules: ["blackfish/1.0.0"]
```

A minimal Tcl modulefile at `<module-root>/blackfish/1.0.0` would contain:

```tcl
#%Module1.0
module load anaconda3/2024.6
prepend-path PATH /scratch/gpfs/DDSS/.blackfish/envs/1.0.0/bin
setenv PYTHONNOUSERSITE 1
```

Cluster administrators should publish it under the site's module search path,
and ensure any Apptainer or other runtime dependencies are also available.
The app initializes environment modules if necessary, purges inherited modules,
and loads the configured module list. An empty module list supports an absolute
shared executable that requires no environment modules.

## Deployment

Clone the app under the appropriate Open OnDemand stage:

```bash
cd "$HOME/ondemand/dev"
git clone https://github.com/princeton-ddss/blackfish-ondemand.git
```

Configure `installations.yml`, verify the shared executable from a visualization
node as a regular app user, and launch a dev session before deploying under
`$HOME/ondemand/share`. Updating the app checkout does not update shared packages.
Open OnDemand may cache the form configuration; use **Help > Restart Web Server**
after changing the catalog if choices do not refresh.

## Launch form

- **Duration:** requested server lifetime in hours.
- **Blackfish Version:** one of the exact shared versions in `installations.yml`.
- **Blackfish Home Directory:** a private absolute path for the database, settings,
  and the initial profile's working files. Defaults to the launching user's `~/.blackfish`;
  created with private permissions if missing. Existing form values may still
  remember `~/.blackfish-ondemand`; no existing data is moved automatically.

## Initial profile

Administrators set the shared cache directory with the top-level `cache_dir` in
`installations.yml`. Users do not select a cache directory in the launch form.
A Python 3 interpreter with the standard library must be available on the job's
PATH; the configured Anaconda module supplies one for the initial installation.

Before initialization, the launcher checks the selected home's `profiles.cfg`.
If any profiles exist, it leaves them and their default selection unchanged.
It does not add, rename, or replace a profile, including any `ondemand` profiles
created by earlier versions of this launcher.

Only when no profiles exist, the launcher creates a Slurm profile named `Default`
with `localhost`, the current user, the selected home directory, and the admin
cache. It marks that profile as the default. The admin cache must exist and be
readable for this initial setup; existing profiles do not depend on its current
value. Users can create, edit, and select other profiles through Blackfish or
its CLI. Old cached `cache_dir` form input is ignored by the launcher.

The profile helper preserves comments and existing configuration. Blackfish then
bootstraps its application data and validates the resolved default before starting
the server. Malformed profile configuration stops startup instead of being
replaced. Changing the admin cache affects initial profile creation in homes
without profiles; it does not update existing profile settings.

Run one session per home directory. Use separate home directories when switching
versions: Blackfish currently runs migrations and records the running version,
but does not compare it with the home directory's previous application version
before making changes. A database migration can make downgrades incompatible.

## Launch feedback and troubleshooting

The session card shows timestamped launch steps in a scrollable log, including
loading the installation, checking profiles, initializing data,
starting the server, and ready/failed. Up to the latest 40 entries are shown;
completed sessions retain that history. `launch-status.txt` contains the complete
launch-step history. It updates when the session card is refreshed by OnDemand
or the page is reloaded; this is not a continuously streamed log.

Detailed Blackfish output remains in `output.log`, accessible through OnDemand's
session-data link. The card displays only launcher progress, not raw Blackfish
output, which can include authentication credentials.

A connection is published only after the login page responds successfully over
HTTP. The launcher detects an early server exit and stops waiting after roughly
120 seconds. Missing shared installations, version mismatches, invalid directories,
and setup errors fail the job instead of proceeding to startup. The card retains
the first failure message; the wrapper does not append a redundant process-exit
error. An initial profile creation failure identifies an unavailable admin cache
and its configured path. Detailed subprocess diagnostics remain in output.log.
The launcher does
not print the authentication token or enable shell tracing. Treat session files
and logs as private because the connection file and application output can contain
credentials.

The server binds to `0.0.0.0`, while proxy URLs retain the node hostname.
This lets the proxy connect through any IPv4 interface on a node with multiple
network interfaces. The readiness probe runs on the compute node; it cannot
verify connectivity from the OnDemand host. If the session is ready but the
Connect button reports a connection failure, check the OnDemand host's DNS,
route, firewall, and proxy configuration for that node and port.

## Local validation

With Ruby and Minitest available:

```bash
ruby test/launcher_test.rb
```

Tests render the real templates and run them with a fake shared executable. They
cover version selection, module loading, literal path handling, first-time profile
creation, preservation of existing profiles, defaults, and settings, setup failures, HTTP
readiness, timeout, early exit, and escaped status HTML.
Actual Slurm submission, modulefiles, proxy login, and shared cache permissions
must be verified with an Open OnDemand dev session on Della.

See `REVIEW.md` for review findings and remaining deployment checks.
