# Blackfish for Open OnDemand

Launch a Blackfish server on a Della visualization node and connect through the
Open OnDemand proxy. Sessions use administrator-managed shared installations.

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
  and the initial default profile's working files. Defaults to the launching
  user's `~/.blackfish-ondemand`; created with private permissions if missing.
- **Cache Directory:** an existing readable absolute path containing shared model
  and image files. Defaults to `/scratch/gpfs/DDSS/.blackfish`.

The app passes both selected directories to `blackfish init`. Existing profiles
are preserved: their cache and working directory are not overwritten by the form.
Change those settings in Blackfish or choose a new home directory to create a new
default profile. Run one session per home directory. Use separate home directories
when switching versions; database migrations can make downgrades incompatible.

## Launch feedback and troubleshooting

The session card shows the most recently recorded launch step: loading the shared
installation, allocating a port, preparing data, initializing the default profile,
starting the server, or ready/failed. Refresh the dashboard page for the latest
step. Completed sessions show their last recorded step. Detailed timestamped
progress and Blackfish output are in `output.log` in the session directory;
`launch-status.txt` contains the current step.

A connection is published only after the login page responds successfully over
HTTP. The launcher detects an early server exit and stops waiting after roughly
120 seconds. Missing shared installations, version mismatches, invalid directories,
and setup errors fail the job instead of proceeding to startup. The launcher does
not print the authentication token or enable shell tracing. Treat session files
and logs as private because the connection file and application output can contain
credentials.

## Local validation

With Ruby and Minitest available:

```bash
ruby test/launcher_test.rb
```

Tests render the real templates and run them with a fake shared executable. They
cover version selection, module loading, literal path handling, setup failures,
profile validation, HTTP readiness, timeout, early exit, and escaped status HTML.
Actual Slurm submission, modulefiles, proxy login, and shared cache permissions
must be verified with an Open OnDemand dev session on Della.

See `REVIEW.md` for review findings and remaining deployment checks.
