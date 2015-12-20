require './src/models/block'

Sequel.migration do
  up do
    alter_table(:blocks) do
      add_column :nextBlockHash, String
    end

    blocks = Block.all
    blocks.each do |block|
      update = DB["UPDATE blocks SET nextBlockHash = ? WHERE blockHash = ?;", block.blockHash, block.previousBlockHash]
      update.update
    end
  end

  down do
    alter_table(:blocks) do
      drop_column :nextBlockHash
    end
  end
end