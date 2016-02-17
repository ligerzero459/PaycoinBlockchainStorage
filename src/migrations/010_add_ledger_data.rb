Sequel.migration do
  up do
    puts '010_add_ledger_data UP'
    alter_table :ledger do
      add_column :blockHash, String
      add_column :height, Fixnum
    end

    require './src/models/ledger'
    require './src/models/transaction'
    require './src/models/block'

    count = Ledger.count()

    (1..count).each do |id|
      entry = Ledger.join(:transactions, :txid=>:txid)
                .join(:blocks, :id=>:transactions__block_id)
                .select(:ledger__id, :blocks__blockHash, :blocks__height, :ledger__txid, :ledger__address, :ledger__type)
                .select_append{sum(:ledger__value).as(value)}
                .select_append{max(:ledger__balance).as(balance)}
                .where(:ledger__id => id).all

      new_entry = Ledger[:id => id]
      if new_entry != nil
        new_entry.update(:height => entry[0].height, :blockHash => entry[0].blockHash)
      end
    end
  end

  down do
    puts '010_add_ledger_data DOWN'
    alter_table :ledger do
      drop_column :blockHash
      drop_column :height
    end
  end
end
