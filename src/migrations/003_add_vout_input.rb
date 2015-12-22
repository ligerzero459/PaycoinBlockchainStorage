require 'json'

require './src/models/input'
require './src/models/output'
require './src/models/transaction'
require './src/models/raw_transaction'

Sequel.migration do
  up do
    alter_table(:inputs) do
      add_column :vout, Fixnum
    end

    Input.set_dataset(:inputs)

    raw_transactions = RawTransaction.all
    raw_transactions.each do |raw_tx|
      json_tx = JSON.parse(raw_tx.raw)
      vins = json_tx.fetch("result").fetch("vin")
      vins.each do |vin|
        if vin['txid'] != nil
          old_input = Input.where(:vout=>nil, :outputTxid=> vin['txid']).first
          old_input.vout = vin['vout'].to_i

          output = Output[:transaction_id=>old_input.outputTransactionId, :n=>old_input.vout]
          old_input.value = output.value

          old_input.save
        end
      end
    end
  end

  down do
    alter_table(:inputs) do
      drop_column :vout
    end
    puts "Unable to undo data changes from migration 3. Fees and input values will still reflect the corrected values"
  end
end
