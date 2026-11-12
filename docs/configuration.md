# Site configuration

Application code is shared. Deployment-specific values live in one YAML mapping.
Examples are committed; active site configuration is managed separately.

## File selection

1. If `BLACKFISH_OOD_CONFIG` is set in the dashboard environment, use that absolute
   path. An empty/relative path or an unreadable/invalid file is an error.
2. Otherwise use `<app-root>/config/site.yml`, ignored by Git.
3. If the chosen file is absent, stop with setup instructions. Examples are never
   implicit fallbacks, and the old `installations.yml` is not read.

For production, an administrator can select a file such as
`/etc/ood/config/apps/blackfish-ondemand/site.yml`. Our loader reads this custom
YAML explicitly; placing it there alone does not configure the application.
Configure the variable in the dashboard environment and restart its web server.
Keep production configuration under site-owned version control or configuration
management. It can be public; separation is about ownership and upgrades.

For dev deployments, copy a chosen example to `config/site.yml`. A dashboard-wide
external override also affects dev apps, so use the appropriate dashboard/process
configuration when testing a different site file. There are no merged override
layers: one selected file is authoritative.

## Schema

```yaml
cluster: example-cluster
cache_dir: /shared/blackfish/cache
default: "1.0.0"
versions:
  "1.0.0":
    executable: /shared/blackfish/envs/1.0.0/bin/blackfish
    modules: []
duration_hours:
  default: 1
  max: 8
```

| Key | Meaning |
| --- | --- |
| `cluster` | Required existing Open OnDemand cluster ID; this app currently targets one cluster per configuration. |
| `cache_dir` | Required absolute cache path for first-time profile creation. It is not used to rewrite existing profiles. |
| `default` | Required exact version key present in `versions`. |
| `versions` | Required nonempty mapping of exact versions to shared installations. It is an offered-version list, not filesystem discovery. |
| `versions.<version>.executable` | Absolute executable path, or `blackfish` supplied by configured modules. |
| `versions.<version>.modules` | Optional array of module names; defaults to empty. |
| `duration_hours.default` | Optional positive integer; defaults to one hour. |
| `duration_hours.max` | Optional integer at least the default; no app-level maximum when omitted. |

Unknown keys, malformed YAML, invalid types, invalid version/default relationships,
and unsuitable executable/module definitions are rejected. This is data-only YAML,
not ERB or arbitrary shell commands. Installation existence and its reported version
are checked on the job node. Cache existence/access is checked only when creating
an initial profile.

For a module-based installation:

```yaml
cluster: gpu-cluster
cache_dir: /work/ai/cache
default: "2.0.0"
versions:
  "2.0.0":
    executable: blackfish
    modules: ["python/3.12", "blackfish/2.0.0"]
```

The module names and paths above are illustrative. Publish modulefiles through
your site's normal module management; this app does not create them.

## Staging and configuration changes

The form reads the selected config on the dashboard. When staging a job, the app
resolves and validates the current site config once for that session. Both shell
templates share that snapshot, embedding the selected executable, modules, and
cache directly. Compute nodes do not need the config file or its environment
variable. Editing configuration later does not alter already-staged jobs.

A cached cluster choice that no longer matches the configured cluster is rejected
with instructions to reload the form. An unavailable version is likewise rejected.
Duration must be a positive integer within the configured maximum, checked during
staging even if browser controls are bypassed. OnDemand/scheduler resource policy
still applies independently. Restart the OnDemand web server if cached form
configuration does not reflect site changes.

## What stays outside this file

Cluster definitions, scheduler connections, accounts/queues, hostname routing,
and proxy access belong in the existing OnDemand configuration. Use OnDemand's
site overrides/sub-apps for form variants rather than copying the launcher.
See [OnDemand sub-app configuration](https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/sub-apps.html).

Generic product behavior stays in shared code: profile creation only when none
exist, the Default name, authentication, readiness handling, and the default app
home. Add configuration options when a concrete site requirement needs them.
