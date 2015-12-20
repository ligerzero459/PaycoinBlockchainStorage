# External dependancies
# Run 'bundler install' to download before running
require 'silkroad'
require 'sqlite3'
require 'sequel'
require 'json'
require 'cliqr'
require 'parseconfig'
require 'os'

# Internal dependancies/models

# Variable declarations
db_version = 2

silkroad = nil
db = nil
highest_block = 1
hash_array = []

cli = Cliqr.interface do
  name 'pbs'
  description 'A Ruby CLI to parse the Paycoin Blockchain into an SQLite database'
  version '0.0.1'
  shell :disable

  handler do
    puts "Please provide a command to run"
  end

  action :parse do
    description 'Parse the Blockchain into an SQLite database'

    option :loadconfig do
      description 'Load a config file in place of RPC Information'
    end

    option :user do
      description 'RPC Username'
    end

    option :pass do
      description 'RPC Username'
      default 'rpcpass'
    end

    option :port do
      description 'RPC Username'
      type :numeric
      default 9001
    end

    option :host do
      description 'RPC Hostname'
      default '127.0.0.1'
    end

    handler do

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

      if @config
        if @loadconfig
          @coin_config = ParseConfig.new(@loadconfig)
        else
          @coin_config = ParseConfig.new(@config)
        end
        
        if !@user
          @user = @coin_config['rpcuser']
        end
        if !@pass
          @pass = @coin_config['rpcpassword']
        end
        if !@host
          @host = "127.0.0.1"
        end
        if !@port
          @port = @coin_config['rpcport']
        end
      else
        @port = Integer('9001')
        @user = "paycoinrpc"
        @pass = "password"
        @host = "127.0.0.1"
      end

      def start_up_rpc
        # RPC credentials here
        paycoin_uri = URI::HTTP.build(["#@user:#@pass", "#@host", Integer(@port), nil, nil, nil])
        silkroad = Silkroad::Client.new paycoin_uri, {}
        silkroad
      end

      def start_up_sequel(silkroad, db_version)
        @db_file = ''
        client_info = silkroad.rpc 'getinfo'
        if client_info.fetch('testnet')
          @db_file = '../XPYBlockchainTestnet.sqlite'
        else
          @db_file = '../XPYBlockchain.sqlite'
        end

        db = Sequel.sqlite(@db_file)

        db.create_table? :blocks do
          primary_key :id
          String :blockHash
          Fixnum :blockSize
          Fixnum :height, :unique=>true
          String :merkleRoot
          DateTime :blockTime
          Float :difficulty
          Float :mint
          String :previousBlockHash
          String :nextBlockHash
          String :flags
          index :blockHash
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
          Fixnum :block_id
          String :type
          Float :totalOutput
          Float :fees
          index :txid
          index :block_id
        end

        db.create_table? :raw_transactions do
          primary_key :id
          String :txid
          File :raw
          index :txid
        end

        db.create_table? :inputs do
          primary_key :id
          Fixnum :transaction_id
          Fixnum :outputTransactionId
          String :outputTxid
          Float :value
          index :transaction_id
          index :outputTransactionId
        end

        db.create_table? :outputs do
          primary_key :id
          Fixnum :transaction_id
          Fixnum :n
          String :script
          String :type
          String :address
          Float :value
          index :address
          index [:transaction_id, :value]
        end

        db.create_table? :schema_info do
          Fixnum :version, :null => false, :default => db_version
        end

        saved_version = db[:schema_info].all
        if saved_version.count == 0
          db.run('INSERT INTO schema_info VALUES(?);', db_version)
        elsif saved_version.count == 1
          if saved_version[0][:version] != db_version
            puts "Database version out of date. Run migrations to update database. Refer to README.md for instructions."
            exit
          end
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

      silkroad = start_up_rpc
      db = start_up_sequel(silkroad, db_version)

      highest_block = db[:blocks].count != 0 ? (db[:blocks].max(:height)) + 1 : 1

      while true
        block_count = silkroad.rpc 'getblockcount'
        if block_count < highest_block
          puts 'No new blocks found.'
        else
          puts 'Total block count: ' << block_count.to_s

          sleep(3)

          (highest_block..200).each do |block_num| hash = silkroad.rpc 'getblockhash', block_num
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
                previousOutputTxid = vin['txid']
                output = Transaction[:txid => previousOutputTxid]
                db_input.outputTxid = previousOutputTxid
                db_input.outputTransactionId = output.id
                total_input += output.totalOutput
                db_input.value = output.totalOutput
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
              else # Assume scrape address
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
            else # set transaction type to normal
              db_transaction.fees = (total_input - total_output).round(6)
              db_transaction.type = 'normal'
            end
            db_transaction.save
          end

          puts 'Block saved: #' << db_block.height.to_s << '/' << block_count.to_s
          # Increase highest block read
          highest_block += 1
          end
        end

        puts 'Checking for new blocks in 60 seconds...'
        sleep(60)
      end

    end

  end
end

cli.execute(ARGV)
