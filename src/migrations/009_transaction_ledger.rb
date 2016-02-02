require 'ostruct'

Sequel.migration do
  up do
    puts '009_transaction_ledger UP'
    create_table? :ledger do
      primary_key :id
      Fixnum :transaction_id
      String :txid
      String :address
      Float :value
      String :type
      Fixnum :n
      Float :balance
      index :txid
      index :address
      index :transaction_id
    end

    require './src/models/input'
    require './src/models/output'
    require './src/models/transaction'
    require './src/models/address'
    require './src/models/ledger'

    addresses = Address.all
    addresses.each do |address|
      if address.address == ''
        next
      end
      transactions = []
      balance = 0.0

      outputs = Output.where(:address => address.address)
      inputs = Input.where(:address => address.address)

      outputs.each do |output|
        if transactions.last != nil
          if transactions.last[:transaction_id] == output.transaction_id
            transactions.last[:value] += output.value.round(6)
          else
            output_hash = {
                transaction_id: output.transaction_id,
                txid: Transaction.where(:id=>output.transaction_id).get(:txid),
                address: output.address,
                value: output.value.round(8),
                type: 'output',
                n: output.n,
                balance: 0.0
            }

            transactions.push output_hash
          end
        else
          output_hash = {
              transaction_id: output.transaction_id,
              txid: Transaction.where(:id=>output.transaction_id).get(:txid),
              address: output.address,
              value: output.value.round(8),
              type: 'output',
              n: output.n,
              balance: 0.0
          }

          transactions.push output_hash
        end
      end

      inputs.each do |input|
        if transactions.detect { |f| f[:transaction_id] == input.transaction_id } != nil
          tx = transactions.detect { |f| f[:transaction_id] == input.transaction_id }
          tx[:value] += -input.value.round(8)
        else
          input_hash = {
              transaction_id: input.transaction_id,
              txid: Transaction.where(:id=>input.transaction_id).get(:txid),
              address: input.address,
              value: -input.value.round(8),
              type: 'input',
              n: input.vout,
              balance: 0.0
          }

          transactions.push input_hash
        end

      end

      transactions.sort_by! { |hsh| [hsh[:transaction_id], hsh[:n]] }

      transactions.each do |tx|
        balance += tx[:value].round(8)
        tx[:balance] = balance.round(8)
        puts tx
        Ledger.create(
            :transaction_id => tx[:transaction_id],
            :txid => tx[:txid],
            :address => tx[:address],
            :value => tx[:value].round(8),
            :type => tx[:type],
            :n => tx[:n],
            :balance => tx[:balance].round(8)
        )
      end
    end
  end

  down do
    puts '009_transaction_ledger DOWN'
    drop_table :ledger
  end
end
