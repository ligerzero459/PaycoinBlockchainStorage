# External dependancies
# Run 'bundler install' to download before running
require 'silkroad'
require 'sqlite3'
require 'sequel'
require 'json'
require 'optparse'
require 'ostruct'
require 'parseconfig'
require 'os'

# Internal dependancies/models

# Variable declarations
db_version = 8

silkroad = nil
db = nil
@highest_block = 1

class OptParse
  def self.parse(args)
    # Set default values for all options
    options = OpenStruct.new
    options.user = "paycoinrpc"
    options.pass = "password"
    options.port = Integer('9001')
    options.host = "127.0.0.1"
    options.adapter = "sqlite"
    options.pathTestnet = "../../XPYBlockchainTestnet.sqlite"
    options.path = "../../XPYBlockchain.sqlite"

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: main.rb [options]"

      # Read config file
      # Specified first so anything can be overridden
      opts.on("-c", "--config", "Use default OS Paycoin configuration file") do |c|
        if OS.windows?
          @appdata = ENV['appdata']
          @config = "#@appdata/Paycoin/paycoin.conf"
        elsif OS.mac?
          @homedir = ENV['HOME']
          @config = "#@homedir/Library/Application Support/Paycoin/paycoin.conf"
          puts @config
        elsif OS.posix?
          @homedir = ENV['HOME']
          @config = "#@homedir/.paycoin/paycoin.conf"
        else
          @config = 'paycoin.conf'
        end

        coin_config = ParseConfig.new(@config)

        options.user = coin_config['rpcuser']
        options.pass = coin_config['rpcpassword']
        options.host = "127.0.0.1"
        options.port = coin_config['rpcport']

      end

      # Separate config file
      # Example config file found in parser.conf.example
      opts.on("-l", "--loadconfig FILEPATH", "Load seperate config file") do |l|
        conf_file = File.expand_path("../../" << l, __FILE__)
        load_config = ParseConfig.new(conf_file)

        # Check for different database adapter
        # Default is sqlite
        if load_config['adapter'] != nil
          options.adapter = load_config['adapter'].downcase
        end

        if load_config['RPC'] != nil
          options.user = load_config['RPC']['username'] != nil ? load_config['RPC']['username'] : options.username
          options.pass = load_config['RPC']['password'] != nil ? load_config['RPC']['password'] : options.password
          options.host = load_config['RPC']['host'] != nil ? load_config['RPC']['host'] : options.host
          options.port = load_config['RPC']['port'] != nil ? load_config['RPC']['port'] : options.port
          puts options
        end

        # If adapter was changed from sqlite, look for database connection info
        if options.adapter == 'postgres'
          puts 'PostgreSQL adapter selected'
          if load_config['postgres'] == nil
            puts 'No PostgreSQL config detected. Exiting...'
            exit
          end
          options.postgres = OpenStruct.new

          # Set all the required info for connecting to database
          options.postgres.username = load_config['postgres']['username']
          options.postgres.password = load_config['postgres']['password']
          options.postgres.host = load_config['postgres']['host']
          options.postgres.database = load_config['postgres']['database']

          if options.postgres.username == nil ||
              options.postgres.password == nil ||
              options.postgres.host == nil ||
              options.postgres.database == nil
            puts "All required database connections settings not available. Please ensure username, password, host" +
              "\nand database name are in config file."
          end
        elsif options.adapter == 'mysql'
          puts 'MySQL adapter selected'
          if load_config['mysql'] == nil
            puts 'No MySQL config detected. Exiting...'
            exit
          end
          options.mysql = OpenStruct.new

          options.mysql.username = load_config['mysql']['username']
          options.mysql.password = load_config['mysql']['password']
          options.mysql.host = load_config['mysql']['host']
          options.mysql.database = load_config['mysql']['database']
        elsif options.adapter == 'sqlite'
          puts 'SQLite adapter selected'

          # New paths do not need to be specified
          # Defaults will be used if nothing is specified
          if load_config['sqlite'] != nil
            options.path = load_config['sqlite']['path'] != nil ? load_config['sqlite']['path'] : options.path
            options.pathTestnet = load_config['sqlite']['pathtestnet'] != nil ? load_config['sqlite']['pathtestnet'] : options.pathTestnet
          end
        else
          puts 'Unsupported adapter detected. Quitting...'
          exit
        end

      end

      opts.on("-ho", "--host HOST", "Specify RPC host") do |host|
        options.host = host
      end

      opts.on("-u", "--username USERNAME", "Specify RPC user") do |user|
        options.user = user
      end

      opts.on("-ps", "--password PASSWORD", "Specify RPC password") do |pass|
        options.pass = pass
      end

      opts.on("-p", "--port PORT", Integer, "Specify RPC port") do |port|
        options.port = port
      end

      # No argument, shows at tail.  This will print an options summary.
      # Try it and see!
      opts.on("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end

    opt_parser.parse!(args)
    options
  end   # parse()
end   # class OptParse

def start_up_rpc(options)
  # RPC credentials here
  paycoin_uri = URI::HTTP.build(["#{options.user}:#{options.pass}", "#{options.host}", Integer(options.port), nil, nil, nil])
  silkroad = Silkroad::Client.new paycoin_uri, {}
  silkroad
end

def check_prev_block(silkroad)
  hash = silkroad.rpc 'getblockhash', @highest_block
  block = silkroad.rpc 'getblock', hash

  prev_block = Block[:blockHash => block.fetch("previousblockhash")]

  if prev_block == nil
    puts 'Previous block didn\'t match. Suspected orphan, redownloading'

    # Find the previous block, find the transactions attached, delete the inputs and outputs attached to said
    # transactions, delete the transactions then delete the block
    prev_block = Block[:height => @highest_block - 1]
    transactions = Transaction.where(:block_id => prev_block.id)
    transactions.each do |tx|
      Output.where(:transaction_id => tx.id).delete
      Input.where(:transaction_id => tx.id).delete
    end
    transactions.delete
    prev_block.delete

    @highest_block -= 1
  end
end

def start_up_sequel(silkroad, db_version, options)
  @db_file = ''
  client_info = silkroad.rpc 'getinfo'
  testnet = client_info.fetch('testnet')
  db = nil

  if options.adapter == 'sqlite'
    if testnet
      @db_file = File.expand_path(options.pathTestnet, __FILE__)
    else
      @db_file = File.expand_path(options.path, __FILE__)
    end

    db = Sequel.sqlite(@db_file)
  elsif options.adapter == 'postgres'
    if testnet
      db = Sequel.postgres(
          :database=>options.postgres.database + "Testnet",
          :host=>options.postgres.host,
          :user=>options.postgres.username,
          :password=>options.postgres.password
      )
    else
      db = Sequel.postgres(
          :database=>options.postgres.database,
          :host=>options.postgres.host,
          :user=>options.postgres.username,
          :password=>options.postgres.password
      )
    end
  elsif options.adapter == 'mysql'
    if testnet
      db = Sequel.connect(
          :adapter=>'mysql2',
          :database=>options.mysql.database + "Testnet",
          :host=>options.mysql.host,
          :user=>options.mysql.username,
          :password=>options.mysql.password
      )
    else
      db = Sequel.connect(
          :adapter=>'mysql2',
          :database=>options.mysql.database,
          :host=>options.mysql.host,
          :user=>options.mysql.username,
          :password=>options.mysql.password
      )
    end
  end

  db.create_table? :schema_info do
    Fixnum :version, :null => false, :default => db_version
  end

  saved_version = db[:schema_info].all
  if saved_version.count == 0
    puts "Database not fully created. Run migrations to create database. Refer to README.md for instructions."
    exit
  elsif saved_version.count == 1
    if saved_version[0][:version] != db_version
      puts "Database version out of date. Run migrations to update database. Refer to README.md for instructions."
      exit
    end
  end

  # Object models for tables
  require_relative  './models/block'
  require_relative  './models/raw_block'
  require_relative  './models/transaction'
  require_relative  './models/raw_transaction'
  require_relative  './models/input'
  require_relative  './models/output'
  require_relative  './models/address'
  require_relative  './models/outstanding_coin'

  puts 'Models loaded'

  # Put genesis block into db if not exists
  genesis_block = db[:blocks]
  if genesis_block.count == 0
    if testnet
      Block.create(
          :blockHash => '0000000f6bb18c77c5b39a25fa03e4c90bffa5cc10d6d9758a1bed5adcee9404',
          :blockSize => 217,
          :height => 0,
          :merkleRoot => '1552f748afb7ff4e04776652c5a17d4073e60b7004e9bca639a99edb82aeb1a0',
          :blockTime => '2014-11-29 00:00:10 UTC',
          :difficulty => 0.06249911,
          :mint => 0.0,
          :previousBlockHash => '',
          :flags => 'proof-of-work stake-modifier'
      )
    else
      Block.create(
          :blockHash => '00000e5695fbec8e36c10064491946ee3b723a9fa640fc0e25d3b8e4737e53e3',
          :blockSize => 217,
          :height => 0,
          :merkleRoot => '1552f748afb7ff4e04776652c5a17d4073e60b7004e9bca639a99edb82aeb1a0',
          :blockTime => '2014-11-29 00:00:10 UTC',
          :difficulty => 0.00024414,
          :mint => 0.0,
          :previousBlockHash => '',
          :flags => 'proof-of-work stake-modifier'
      )
    end
    puts 'Genesis block saved.'
  end

  db
end

def parse_block(block_num, silkroad, block_count)
  hash = silkroad.rpc 'getblockhash', block_num
  block = silkroad.rpc 'getblock', hash

  # Parse raw block into JSON
  db_raw_block = RawBlock.new
  db_raw_block.raw = JSON.pretty_generate(block)

  db_block = Block.new

  # Put block data into new Block model
  height = block.fetch("height").to_i
  db_block.blockHash = hash
  db_block.height = height
  db_raw_block.height = height
  db_block.blockSize = block.fetch("size").to_i
  db_block.merkleRoot = block.fetch("merkleroot")
  db_block.difficulty = block.fetch("difficulty").to_f
  db_block.blockTime = block.fetch("time")
  db_block.mint = block.fetch("mint")
  db_block.previousBlockHash = block.fetch("previousblockhash")
  db_block.flags = block.fetch("flags")
  db_block.save
  db_raw_block.save

  # Update previous block's 'nextBlockHash'
  Block[:blockHash => db_block.previousBlockHash].update(:nextBlockHash => db_block.blockHash)

  # Grab all block transactions and decode them
  raw_txs = silkroad.batch do
    block['tx'].each do |tx|
      rpc 'getrawtransaction', tx
    end
  end

  decoded_txs = silkroad.batch do
    raw_txs.each do |raw_tx|
      rpc 'decoderawtransaction', raw_tx['result']
    end
  end

  # Loop through all transactions and process inputs and outputs
  decoded_txs.each do |decoded_tx|
    result = decoded_tx.fetch("result")
    txid = result.fetch("txid")
    reward_block = false

    RawTransaction.create(:txid => txid, :raw => JSON.pretty_generate(decoded_tx))
    db_transaction = Transaction.create(
        :txid => txid,
        :block_id => db_block.id
    )

    vins = result.fetch("vin")
    total_input = 0

    # Process all inputs
    vins.each_with_index do |vin, i|
      db_input = Input.create(
          :transaction_id => db_transaction.id
      )

      if vin['coinbase'] != nil
        reward_block = true
      else
        db_input.vout = vin['vout']
        previousOutputTxid = vin['txid']
        output_tx = Transaction[:txid => previousOutputTxid]
        db_input.outputTxid = previousOutputTxid
        db_input.outputTransactionId = output_tx.id
        output = Output[:transaction_id => output_tx.id, :n => db_input.vout]
        total_input += output.value.round(6)
        db_input.value = output.value.round(6)
        db_input.address = output.address

        address = Address[:address => db_input.address]
        if address == nil
          address = Address.create(
              :address=>db_input.address,
              :balance=>db_input.value
          )
        else
          address.update(:balance => address.balance - db_input.value)
        end

        address.save
        db_input.save
      end
    end

    vouts = result.fetch("vout")
    total_output = 0
    stake = false

    # Loop through all outputs
    vouts.each do |vout|
      value = vout.fetch("value")
      total_output += value.round(6)
      n = vout.fetch("n")
      script = vout.fetch("scriptPubKey")
      asm = script.fetch("asm")
      type = script.fetch("type")
      if type == 'nonstandard'
        if asm == '' || asm == 'OP_MICROPRIME'
          stake = true
        end
      end
      address = ''
      if type == "pubkey" || type == "pubkeyhash"
        address = script.fetch("addresses")[0]
      end

      address_out = Address[:address => address]
      if address_out == nil
        address_out = Address.create(
            :address=>address,
            :balance=>value
        )
      else
        address_out.update(:balance => address_out.balance + value)
      end

      # Save output to database
      Output.create(
          :transaction_id => db_transaction.id,
          :n => n, :script => asm,
          :type => type,
          :address => address,
          :value => value
      )
      address_out.save
    end

    db_transaction.totalOutput = total_output.round(6)
    if stake && vouts.length > 2
      #set transaction type to PoS-Reward
      if vouts[1].fetch("scriptPubKey").fetch("addresses")[0] == vouts[2].fetch("scriptPubKey").fetch("addresses")[0]
        # Normal stake with no scrape address
        stake_amount = total_output - total_input
        db_transaction.fees = stake_amount.round(6)
        db_transaction.type = 'PoS-Reward'
        db_transaction.coinstake = true
      else # Assume scrape address
        stake_amount = vouts[2].fetch("value")
        db_transaction.fees = stake_amount.round(6)
        db_transaction.type = 'PoS-Reward'
        db_transaction.coinstake = true
      end
    elsif stake && vouts.length == 2
      # Stake edge case where stake only has one transaction
      stake_amount = total_output - total_input
      db_transaction.fees = stake_amount.round(6)
      db_transaction.type = 'PoS-Reward'
      db_transaction.coinstake = true
    elsif stake && reward_block
      # Coinbase of stake transaction
      db_transaction.fees = total_output - total_input
      db_transaction.type = 'PoS-Reward'
      db_transaction.coinbase = true
    elsif !stake && reward_block
      # set transaction type to PoW-Reward
      db_transaction.fees = total_output.round(6)
      db_transaction.type ='PoW-Reward'
    else # set transaction type to normal
      db_transaction.fees = (total_input - total_output).round(6)
      db_transaction.type = 'normal'
    end
    db_transaction.save
  end

  puts 'Block saved: #' << db_block.height.to_s << '/' << block_count.to_s
  # Increase highest block read
  @highest_block += 1
end

options = OptParse.parse(ARGV)

silkroad = start_up_rpc(options)
db = start_up_sequel(silkroad, db_version, options)

puts "DB started"

@highest_block = db[:blocks].count != 0 ? (db[:blocks].max(:height)) + 1 : 1

while true
  puts "Getting block count..."
  client_info = silkroad.rpc 'getinfo'
  OutstandingCoin.create(:coinSupply=>client_info.fetch('moneysupply').round(8))
  block_count = silkroad.rpc 'getblockcount'
  if block_count < @highest_block
    puts 'No new blocks found.'
  else
    puts 'Total block count: ' << block_count.to_s

    sleep(3)
    check_prev_block(silkroad)

    (@highest_block..block_count).each do |block_num|
      db.transaction do
        parse_block(block_num, silkroad, block_count)
      end
    end
  end

  puts 'Checking for new blocks in 60 seconds...'
  sleep(60)
end
