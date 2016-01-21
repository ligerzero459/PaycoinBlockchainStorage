require 'ostruct'

Sequel.migration do
  up do
    puts '007_address_balances UP'
    create_table? :addresses do
      primary_key :id
      String :address
      Float :balance
      index :address
    end

    require './src/models/input'
    require './src/models/output'
    require './src/models/address'

    outputs = Output.select_group(:address).select_append{sum(:value).as(balance)}
    outputs.each do |output|
      if output.address == nil || output.address == ""
        next
      end
      temp = OpenStruct.new
      temp.address = output.address
      out_bal = Output.where(:address=>temp.address).sum(:value)
      in_bal = Input.where(:address=>temp.address).sum(:value)
      if in_bal != nil
        bal = out_bal.round(6) - in_bal.round(6)
      else
        bal = out_bal.round(6)
      end
      temp.balance = bal.round(6)
      Address.create(
          :address => temp.address,
          :balance => temp.balance
      )
    end
  end

  down do
    puts '007_address_balances DOWN'
    drop_table :addresses
  end
end
