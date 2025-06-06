# Blackfish
This is the Open OnDemand application for the Blackfish project at Princeton University. It runs the
Blackfish server on a Della visualization node with minimal resources. Once the server is launched,
users authenticate and interact with the server in their browser via the Blackfish UI.


## Deployment

### Setup
For `STAGE = 'dev', 'share'`:
```shell
# Download OnDemand code
cd $HOME/ondemand/$STAGE && git clone https://github.com/princeton-ddss/blackfish-ondemand.git
cd blackfish-ondemand
git pull
# Download Blackfish code
mkdir src
git clone https://github.com/princeton-ddss/blackfish.git
git clone https://github.com/princeton-ddss/blackfish-ui.git
# Create conda environment
module load anaconda3/2024.6
conda create --prefix $HOME/ondemand/$STAGE/blackfish-ondemand/.venv python=3.12
conda activate $HOME/ondemand/$STAGE/blackfish-ondemand/.venv python=3.12
conda install nodejs
# Install Blackfish
pip install src/blackfish
cd src/blackfish-ui
npx update-browserslist-db@latest
npm install .
```

> [!NOTE]
> The Blackfish API source code is only needed for development and testing purposes. For deployment, you can simply `pip install blackfish-ai`.

### Testing
To test changes, simply checkout the new commit and run the application. For example,
```shell
# blackfish
cd $HOME/ondemand/dev/blackfish-ondemand/src/blackfish
git fetch origin
git checkout pri-123-fix-the-thing
git pull origin
module load anconda3/2024.6
pip install src/blackfish
# blackfish-ui
cd $HOME/ondemand/dev/blackfish-ondemand/src/blackfish-ui
git fetch origin
git checkout pri-123-fix-the-thing
git pull origin
module load anconda3/2024.6
npx update-browserslist-db@latest
npm install .
```

### Production
Pushing updates to production involves the same process as above applied to the production directory: pull and install changes to the source code in `$HOME/ondemand/share/blackfish-ondemand` (or just `pip install --upgrade blackfish-ai` for the API).


## Service Updates
Updating service versions is simply matter of updating the default image version specified in the `Blackfish` source code. Thus, it is the same process as deploying a new version of `blackfish` and ensuring that the new image version is made available in the shared cache directory, `/scratch/gpfs/ddsscloud/.blackfish/images`.
