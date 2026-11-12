# Princeton Della deployment example

This is one public, deployment-specific example. Its paths and module names are
not shared application defaults and are not loaded automatically.

The example config at `config/examples/princeton-della.yml` selects:

- Open OnDemand cluster `della-vis2`.
- Shared cache `/scratch/gpfs/DDSS/.blackfish`.
- Blackfish 1.0.0 at `/scratch/gpfs/DDSS/.blackfish/envs/1.0.0/bin/blackfish`.
- Runtime module `anaconda3/2024.6`.

Verify the paths, permissions, available modules, and supported Python version
on the target nodes before deploying. Provision images in the shared cache using
the Blackfish administration workflow.

## Shared installation

Run once as the shared installation owner, into a fresh destination:

```bash
module load anaconda3/2024.6
umask 022
install_dir=/scratch/gpfs/DDSS/.blackfish/envs/1.0.0
test ! -e "$install_dir" || exit 1
python -m venv "$install_dir"
"$install_dir/bin/python" -m pip install 'blackfish-ai==1.0.0'
PYTHONNOUSERSITE=1 "$install_dir/bin/blackfish" version
```

Ordinary app users need read and execute access to the installation and all parent
directories. Only installation administrators should have write access. Keep the
example's runtime module list until a site-managed Blackfish module is available;
then update the site config to name that module and its `blackfish` executable.

## Dev configuration and migration

After updating a dev app checkout to this configuration layout:

```bash
cd "$HOME/ondemand/dev/blackfish-ondemand"
cp config/examples/princeton-della.yml config/site.yml
```

Review and adjust the copied file. It is ignored by Git. The former root
`installations.yml` is removed; old settings must be migrated explicitly rather
than silently continuing to select this institution's deployment.

Use **Help > Restart Web Server** and reopen the form after changing configuration.
Launch with a temporary fresh app home, then with an existing home, to check
initial Default creation and preservation of existing profiles/defaults. No
existing `~/.blackfish-ondemand` data is moved or renamed.

For production, maintain the actual config separately (for example in a Princeton
configuration repository) and select its absolute deployed path with
`BLACKFISH_OOD_CONFIG` in the dashboard environment. Pin the shared app revision
independently of site configuration. Updating application code should not require
editing tracked templates or overwriting site settings.

## Validation history and remaining checks

The previous app revision was tested in Della dev: startup, proxy browser access,
form-cache refresh, and deliberate cache/profile failures were observed. Listening
on all IPv4 interfaces fixed the earlier proxy connectivity failure.

This configuration refactor still needs a Della dev retest. Confirm the copied
site config is selected, the expected module/executable/cache are used, the form
shows the correct cluster/version choices, startup and authentication work, and
both fresh/existing homes behave correctly. Local tests do not establish site
routing, Slurm submission, modulefile correctness, or shared cache permissions.
