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

After all required gems are installed, make sure that your wallet is running with `rpcuser=paycoinrpc, rpcpassword=passwprd, rpcport=9001` in your `paycoin.conf`. To run the parser, type

`ruby main.rb`

inside of the src directory.

####TODO:
***
Command-line args for rpcuser, password and port