# Blackfish
This is the Open OnDemand application for the Blackfish project at Princeton University. It runs the
Blackfish server on a Della visualization node with minimal resources. Once the server is launched,
users authenticate and interact with the server in their browser via the Blackfish UI.

## Setup
Until Blackfish is globally available as a module or tool (i.e., `/user/bin/blackfish`), users must
manually install and setup Blackfish before launching the OnDemand application:

```shell
# Install Blackfish to `base` environment
module load anaconda3/2024.6
pip install blackfish
which blackfish # check installation worked

# Setup Blackfish
blackfish init
# Enter these values at the prompts:
# name = default
# type = slurm
# host = localhost
# user = $whoami
# home_dir = $HOME/.blackfish
# cache_dir = /scratch/gpfs/ddsscloud/.blackfish
```

## Dev

## Prod

## Deployment
Note:
`/ondemand/dev/blackfish-ondemand -> /scratch/gpfs/ddsscloud/.blackfish/envs/dev` and `/scratch/gpfs/ddsscloud/.blackfish/images/blackfish-ui:dev`?
`/ondemand/shared/blackfish-ondemand -> /scratch/gpfs/ddsscloud/.blackfish/envs/shared` and `/scratch/gpfs/ddsscloud/.blackfish/images/blackfish-ui:latest`?

(Hmm... but we need each ondemand directory to use the same GitHub repo...so code needs to discover environment somehow...)

### Updating `blackfish-ondemand`
1. Test changes by modifying `/ondemand/dev/blackfish-ondemand` and running on `mydella-test.princeton.edu`
2. Push/merge changes to `main` branch
3. Pull changes to `/ondemand/shared/blackfish-ondemand`

### Updating `blackfish`
1. Push/merge changes to `main` branch
2. Create a release/tag
3. `pip install update blackfish` in `/shared/gpfs/ddsscloud/.blackfish/envs/dev`
4. Test changes by running on `mydella-test.princeton.edu` *using dev application* (`/ondemand/dev/blackfish-ondemand`)
5. `pip install update blackfish` in `/shared/gpfs/ddsscloud/.blackfish/envs/prod`
6. (Optional) If release/tag includes update to UI, then:
   a. `docker push blackfish-ui:latest`
   b. `apptainer pull docker://blackfish-ui:latest` to `/shared/gpfs/ddsscloud/.blackfish/images/blackfish-ui_latest`

### Updating `blackfish-ui`


### Updating services
