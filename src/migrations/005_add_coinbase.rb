Sequel.migration do
  up do
    puts '005_add_coinbase.rb UP'
    alter_table(:transactions) do
      add_column :coinbase, TrueClass, :default => false
      add_column :coinstake, TrueClass, :default => false
    end

    require './src/models/transaction'

    Transaction.where(:type => 'PoS-Reward', :totalOutput => 0.0, :fees => 0.0).update(:coinbase => true)
    Transaction.where(:type => 'PoS-Reward').where{totalOutput > 0.0}.update(:coinstake => true)
  end

  down do
    puts '005_add_coinbase.rb DOWN'
    alter_table(:transactions) do
      drop_column :coinbase
      drop_column :coinstake
    end
  end
end
