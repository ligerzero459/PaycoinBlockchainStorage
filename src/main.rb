# External dependancies
# Run 'bundler install' to download before running
require 'silkroad'
require 'sqlite3'
require 'json'
require 'benchmark'

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

  db
end

silkroad = start_up_rpc
db = start_up_db

hash = silkroad.rpc 'getblockhash', 1


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
