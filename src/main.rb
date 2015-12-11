# External dependancies
# Run 'bundler install' to download before running
require 'silkroad'
require 'sqlite3'
require 'sequel'
require 'json'

# Variable declarations
silkroad = nil
db = nil
highest_block = 0
hash_array = []

def start_up_rpc
  paycoinURI = URI::HTTP.build(['ligerzero459:k3ep48dl_s', '127.0.0.1', 9001, nil, nil, nil])
  silkroad = Silkroad::Client.new paycoinURI, {}

  silkroad
end

def start_up_sequel
  db = Sequel.sqlite('../XPYBlockchain.sqlite')

  db.create_table? :blocks do
    primary_key :id
    String :hash, :unique=>true
    Fixnum :height, :unique=>true
    String :blockTime
    Float :mint
    String :previousBlockHash
    String :flags
  end

  db.create_table? :raw_blocks do
    primary_key :id
    Fixnum :height
    File :raw
  end

  db.create_table? :transactions do
    primary_key :id
    String :txid
    Fixnum :blockId
    Float :totalOutput
    Float :fees
  end

  db.create_table? :raw_transactions do
    primary_key :id
    String :txid
    File :raw
  end

  db.create_table? :inputs do
    primary_key :id
    Fixnum :transactionId
    Fixnum :outputTransactionId
    String :outputTxid
    Float :value
  end

  db.create_table? :outputs do
    primary_key :id
    Fixnum :transactionId
    Fixnum :n
    String :script
    String :type
    String :address
    Float :value
  end

  db
end

silkroad = start_up_rpc
db = start_up_sequel

# hash = silkroad.rpc 'getblockhash', 2554
hash = silkroad.rpc 'getblockhash', 403165
block = silkroad.rpc 'getblock', hash

puts JSON.pretty_generate(block)

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
  puts decoded_tx.fetch("result")
  result = decoded_tx.fetch("result")
  puts 'txid: ' << result.fetch("txid")
  vins = result.fetch("vin")

  vins.each_with_index do |vin, i|
    if vin['coinbase'] != nil
      puts 'coinbase: ' << vin['coinbase']
    else
      puts 'input tx: ' << vin['txid']
    end
  end

  vouts = result.fetch("vout")
  vouts.each do |vout|
    puts 'script: ' << vout.fetch("scriptPubKey").fetch("asm")
    puts ''
  end
end



# Code for multiple blocks
# Will be updated once single block and transactions are read into DB

# block_count =  silkroad.rpc 'getblockcount'
# puts block_count
#
# (highest_block..block_count).each do |block_num|
#   hash = silkroad.rpc 'getblockhash', block_num
#   hash_array.push(hash)
#   puts block_num.to_s + " | " + hash
# end
