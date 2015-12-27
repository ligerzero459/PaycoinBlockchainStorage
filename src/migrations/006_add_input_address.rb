Sequel.migration do
  up do
    puts '006_add_input_address UP'
    alter_table (:inputs) do
      add_column :address, String
      add_index :address
    end

    require './src/models/input'
    require './src/models/output'

    inputs = Input.all
    inputs.each do |input|
      output = Output[:transaction_id => input.outputTransactionId, :n => input.vout]

      if output != nil
        input.address = output.address
        input.save
      end
    end
  end

  down do
    puts '006_add_input_address DOWN'
    alter_table (:inputs) do
      drop_column :address
    end
  end
end
