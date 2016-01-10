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
db_version = 6

silkroad = nil
db = nil
@highest_block = 1

class OptParse
  def self.parse(args)
    # Set default values for all options
    options = OpenStruct.new
    options.loadconfig = ""
    options.user = "paycoinrpc"
    options.pass = "password"
    options.port = Integer('9001')
    options.host = "127.0.0.1"

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

      opts.on("-l", "--loadconfig", "Load seperate config file") do |l|
        
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

def start_up_sequel(silkroad, db_version)
  @db_file = ''
  client_info = silkroad.rpc 'getinfo'
  if client_info.fetch('testnet')
    @db_file = File.expand_path('../../XPYBlockchainTestnet.sqlite', __FILE__)
  else
    @db_file = File.expand_path('../../XPYBlockchain.sqlite', __FILE__)
  end

  db = Sequel.sqlite(@db_file)

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

  puts 'Models loaded'

  # Put genesis block into db if not exists
  genesis_block = db[:blocks]
  if genesis_block.count == 0
    if client_info.fetch("testnet")
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

  db_raw_block = RawBlock.new
  db_raw_block.raw = JSON.pretty_generate(block)

  db_block = Block.new

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

      # Save output to database
      Output.create(
          :transaction_id => db_transaction.id,
          :n => n, :script => asm,
          :type => type,
          :address => address,
          :value => value
      )
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
db = start_up_sequel(silkroad, db_version)

puts "DB started"

@highest_block = db[:blocks].count != 0 ? (db[:blocks].max(:height)) + 1 : 1

while true
  puts "Getting block count..."
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