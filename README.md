# Paycoin Blockchain Storage

Paycoin Blockchain Storage uses RPC commands to get data from a local wallet and then parse that data into an SQLite database.

Works with wallets in both mainnet and testnet modes, checking which mode the wallet is running before putting the correct genesis block into the database. On Linux and Mac, this will complete at a decent speed. However, due to RPC issues, on Windows this will run incredibly slowly.

Currently no support for command line arguments, but that is on the list of things to add.

####Running PBS:
***
Ensure you have Ruby 2.2.1 installed. Instructions to install Ruby correctly can be found on the [RVM site](http://rvm.io/). Once installed, you will also need Bundler, which can be installed through RubyGems.

`gem install bundler`

Clone the repo, navigate to the src directory and run

`bundle install`

After all required gems are installed, make sure that your wallet is running with `rpcuser=paycoinrpc, rpcpassword=password, rpcport=9001` in your `paycoin.conf`. To run the parser, type

`ruby main.rb parse`

inside of the src directory.

##### Upgrading database

After pulling a new version, run ensure you run Sequel migrations to get your database up to date. For SQLite, run

`sequel -m src/migrations sqlite://path_to_database`

##### Usage

To run PBS after installation

`ruby main.rb parse`

**Available options:**

    --config  :  Load a config file in place of RPC Information
    --user  :  RPC Username
    --pass  :  RPC Username (default => "rpcpass")
    --port  :  <numeric> RPC Username (default => 9001)
    --host  :  RPC Hostname (default => "127.0.0.1")
    --help, -h  :  Get helpful information for action "pbs parse" along with its usage information.

The main command will allow the following commands.

**Available commands:**

    parse -- Parse the Blockchain into an SQLite database
    help -- The help action for command "pbs" which provides details and usage information on how to use the command.
    version -- Get version information for command "pbs".

####TODO:
***
Speed it up