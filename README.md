# Blackfish

This is the Open OnDemand application for the Blackfish project at Princeton University. It runs the
Blackfish server on a Della visualization node with minimal resources. Once the server is launched,
users authenticate and interact with the server in their browser via the Blackfish UI.

## Deployment

### Setup

For `STAGE = 'dev', 'share'`:

```shell
cd $HOME/ondemand/$STAGE && git clone https://github.com/princeton-ddss/blackfish-ondemand.git
```

That's it. The application automatically:

- Creates a per-user conda environment at `~/.blackfish-ondemand/.venv`
- Installs the correct version of `blackfish-ai` (specified in `.blackfish-version`)

### Updating Blackfish Version

The required Blackfish version is specified in `.blackfish-version`. To update:

1. Test the new version of `blackfish-ai` in the dev environment
2. Update `.blackfish-version` with the new version number
3. Commit and push the change
4. Pull the change to `$HOME/ondemand/$STAGE`

Users will automatically get the new version on their next session.

### Testing

To test changes to blackfish-ondemand, checkout the branch and run the application:

```shell
cd $HOME/ondemand/dev/blackfish-ondemand
git fetch origin
git checkout pri-123-fix-the-thing
git pull origin
```

### Production

Pull the latest changes to the production directory:

```shell
cd $HOME/ondemand/share/blackfish-ondemand
git pull origin main
```

## Service Updates

Updating service versions is simply a matter of updating the default image version specified in the Blackfish source code. Ensure the new image version is available in the shared cache directory at `/scratch/gpfs/ddsscloud/.blackfish/images`.
