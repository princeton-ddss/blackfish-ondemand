# Blackfish
This is the Open OnDemand application for the Blackfish project at Princeton University. It runs the
Blackfish server on a Della visualization node with minimal resources. Once the server is launched,
users authenticate and interact with the server in their browser via the Blackfish UI.

## Setup
Until Blackfish is globally available as a module or tool (i.e., `/user/bin/blackfish`), users must
manually install and setup Blackfish before launching the OnDemand application:
```
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
