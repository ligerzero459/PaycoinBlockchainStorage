# External dependancies
# Run 'bundler install' to download before running
require 'silkroad'
require 'sqlite3'
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

def start_up_db
  db = SQLite3::Database.open('../XPYBlockchain.sqlite')

  # Create tables if they don't exist
  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='blocks'")
  if exists.length == 0
    db.execute("CREATE TABLE IF NOT EXISTS `blocks` (
      `id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      `hash`	TEXT NOT NULL UNIQUE,
      `height`	INTEGER UNIQUE,
      `blockTime`	TEXT,
      `mint`	REAL,
      `previousBlockHash`	TEXT,
      `flags`	TEXT
    )")
  end

  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='raw_blocks'")
  if exists.length == 0
    db.execute("CREATE TABLE IF NOT EXISTS `raw_blocks` (
      `id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      `height`	INTEGER,
      `raw`	BLOB
    )")
  end

  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'")
  if exists.length == 0
    db.execute("CREATE TABLE IF NOT EXISTS `transactions` (
      `id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      `txid`	TEXT,
      `blockId`	INTEGER,
      `totalOutput`	REAL,
      `fees`	REAL
    )")
  end

  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='raw_transactions'")
  if exists.length == 0
    db.execute("CREATE TABLE IF NOT EXISTS `raw_transactions` (
      `id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      `txid`	TEXT,
      `raw`	BLOB
    )")
  end

  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='inputs'")
  if exists.length == 0
    db.execute("CREATE TABLE IF NOT EXISTS `inputs` (
      `id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      `transactionId`	INTEGER,
      `outputTransactionId`	INTEGER,
      `outputTxid`	TEXT,
      `value`	REAL
    )")
  end

  exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='outputs'")
  if exists.length == 0
    db.execute("CREATE TABLE IF NOT EXISTS `outputs` (
      `id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      `transactionId`	INTEGER,
      `n`	INTEGER,
      `script`	TEXT,
      `type`	TEXT,
      `address`	TEXT,
      `value`	REAL
    )")
  end

  # return completed db
  db
end

silkroad = start_up_rpc
# db = start_up_db
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
