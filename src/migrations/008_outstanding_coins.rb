require 'ostruct'

Sequel.migration do
  up do
    puts '008_outstanding_coins UP'
    create_table? :outstanding_coins do
      primary_key :id
      Float :coinSupply
      DateTime :createdAt
      DateTime :updatedAt
    end
  end

  down do
    puts '008_outstanding_coins DOWN'
    drop_table :outstanding_coins
  end
end
