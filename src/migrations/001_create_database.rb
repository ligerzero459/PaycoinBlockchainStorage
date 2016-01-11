Sequel.migration do
  up do
    puts '001_create_database.rb UP'
    create_table? :blocks do
      primary_key :id
      String :blockHash
      Fixnum :height, :unique=>true
      DateTime :blockTime
      Float :mint
      String :previousBlockHash
      String :flags
      index :blockHash
      index :height
    end

    create_table? :raw_blocks do
      primary_key :id
      Fixnum :height
      File :raw, :size=>:long
      index :height
    end

    create_table? :transactions do
      primary_key :id
      String :txid
      Fixnum :block_id
      String :type
      Float :totalOutput
      Float :fees
      index :txid
      index :block_id
    end

    create_table? :raw_transactions do
      primary_key :id
      String :txid
      File :raw, :size=>:long
      index :txid
    end

    create_table? :inputs do
      primary_key :id
      Fixnum :transaction_id
      Fixnum :outputTransactionId
      String :outputTxid
      Float :value
      index :transaction_id
      index :outputTransactionId
    end

    create_table? :outputs do
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
  end

  down do
    puts '001_create_database.rb DOWN'
    drop_table :outputs
    drop_table :inputs
    drop_table :raw_transactions
    drop_table :raw_blocks
    drop_table :transactions
    drop_table :blocks
  end
end
