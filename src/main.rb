# External dependancies
# Run 'bundler install' to download before running
require 'silkroad'
require 'sqlite3'
require 'sequel'
require 'json'

# Internal dependancies/models


# Variable declarations
silkroad = nil
db = nil
highest_block = 1
hash_array = []

def start_up_rpc
  # RPC credentials here
  paycoin_uri = URI::HTTP.build(['paycoinrpc:password', '127.0.0.1', 9001, nil, nil, nil])
  silkroad = Silkroad::Client.new paycoin_uri, {}

  silkroad
end

def start_up_sequel(silkroad)
  db = Sequel.sqlite('../XPYBlockchain.sqlite')

  db.create_table? :blocks do
    primary_key :id
    String :hash, :unique=>true
    Fixnum :height, :unique=>true
    DateTime :blockTime
    Float :mint
    String :previousBlockHash
    String :flags
    index :hash
    index :height
  end

  db.create_table? :raw_blocks do
    primary_key :id
    Fixnum :height
    File :raw
    index :height
  end

  db.create_table? :transactions do
    primary_key :id
    String :txid
    Fixnum :blockId
    String :type
    Float :totalOutput
    Float :fees
    index :txid
    index :blockId
  end

  db.create_table? :raw_transactions do
    primary_key :id
    String :txid
    File :raw
    index :txid
  end

  db.create_table? :inputs do
    primary_key :id
    Fixnum :transactionId
    Fixnum :outputTransactionId
    String :outputTxid
    Float :value
    index :transactionId
    index :outputTransactionId
  end

  db.create_table? :outputs do
    primary_key :id
    Fixnum :transactionId
    Fixnum :n
    String :script
    String :type
    String :address
    Float :value
    index :address
    index [:transactionId, :value]
  end

  # Object models for tables
  require './models/block'
  require './models/raw_block'
  require './models/transaction'
  require './models/raw_transaction'
  require './models/input'
  require './models/output'

  # Put genesis block into db if not exists
  genesis_block = db[:blocks]
  if genesis_block.count == 0
    client_info = silkroad.rpc 'getinfo'
    if client_info.fetch("testnet")
      Block.create(
          :hash => '0000000f6bb18c77c5b39a25fa03e4c90bffa5cc10d6d9758a1bed5adcee9404',
          :height => 0,
          :blockTime => '2014-11-29 00:00:10 UTC',
          :mint => 0.0,
          :previousBlockHash => '',
          :flags => 'proof-of-work stake-modifier'
      )
    else
      Block.create(
          :hash => '00000e5695fbec8e36c10064491946ee3b723a9fa640fc0e25d3b8e4737e53e3',
          :height => 0,
          :blockTime => '2014-11-29 00:00:10 UTC',
          :mint => 0.0,
          :previousBlockHash => '',
          :flags => 'proof-of-work stake-modifier'
      )
    end
    puts 'Genesis block saved.'
  end

  db
end

silkroad = start_up_rpc
db = start_up_sequel(silkroad)

block_count =  silkroad.rpc 'getblockcount'
puts 'Total block count: ' << block_count.to_s
highest_block = db[:blocks].count != 0 ? (db[:blocks].max(:height)) + 1 : 1

sleep(3)

(highest_block..block_count).each do |block_num|
  hash = silkroad.rpc 'getblockhash', block_num
  block = silkroad.rpc 'getblock', hash

  db_raw_block = RawBlock.new
  db_raw_block.raw = JSON.pretty_generate(block)

  db_block = Block.new

  height = block.fetch("height").to_i
  time = block.fetch("time")
  mint = block.fetch("mint")
  prev_block_hash = block.fetch("previousblockhash")
  flags = block.fetch("flags")
  db_block.hash = hash
  db_block.height = height
  db_raw_block.height = height
  db_block.blockTime = time
  db_block.mint = mint
  db_block.previousBlockHash = prev_block_hash
  db_block.flags = flags
  db_block.save
  db_raw_block.save

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
    db_transaction = Transaction.create(:txid => txid, :blockId => db_block.id)

    vins = result.fetch("vin")
    total_input = 0

    vins.each_with_index do |vin, i|
      db_input = Input.create(:transactionId => db_transaction.id)

      if vin['coinbase'] != nil
        reward_block = true
      else
        previousOutputTxid = vin['txid']
        output = Output[:transactionId => Transaction[:txid => previousOutputTxid].id]
        db_input.outputTxid = previousOutputTxid
        db_input.outputTransactionId = output.transactionId
        total_input += output.value
        db_input.value = output.value
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
          :transactionId => db_transaction.id,
          :n => n,
          :script => asm,
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
      else
        # Assume scrape address
        stake_amount = vouts[2].fetch("value")
        db_transaction.fees = stake_amount.round(6)
        db_transaction.type = 'PoS-Reward'
      end
    elsif stake && vouts.length == 2
      # Stake edge case where stake only has one transaction
      stake_amount = total_output - total_input
      db_transaction.fees = stake_amount.round(6)
      db_transaction.type = 'PoS-Reward'
    elsif !stake && reward_block
      # set transaction type to PoW-Reward
      db_transaction.fees = total_output.round(6)
      db_transaction.type ='PoW-Reward'
    else
      # set transaction type to normal
      db_transaction.fees = (total_input - total_output).round(6)
      db_transaction.type = 'normal'
    end
    db_transaction.save
  end

  puts 'Block saved: #' << db_block.height.to_s
  # Increase highest block read
  highest_block += 1
end
