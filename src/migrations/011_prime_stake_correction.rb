Sequel.migration do
  up do
    puts '011_prime_stake_correction.rb UP'
    alter_table(:transactions) do
      add_column :primestake, TrueClass, :default => false
    end

    require './src/models/transaction'
    require './src/models/output'

    prime_stakes = Output.where(Sequel.like(:script, '%OP_PRIME%'))

    prime_stakes.each do |ps|
      Transaction.where(:id => ps.transaction_id).update(:primestake => true,
                                                         :coinstake => true,
                                                         :type => 'PoS-Reward',
                                                         :fees => Sequel.expr(:fees) * -1)
    end
  end

  down do
    puts '011_prime_stake_correction.rb DOWN'
    alter_table(:transactions) do
      drop_column :primestake
    end
  end
end
