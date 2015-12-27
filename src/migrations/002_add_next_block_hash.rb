require './src/models/block'

Sequel.migration do
  up do
    puts '002_add_next_block_hash.rb UP'
    alter_table(:blocks) do
      add_column :nextBlockHash, String
    end

    blocks = Block.all
    blocks.each do |block|
      puts block.height.to_s << "/" << blocks.count.to_s << " blocks processed"
      update = DB["UPDATE blocks SET nextBlockHash = ? WHERE blockHash = ?;", block.blockHash, block.previousBlockHash]
      update.update
    end
  end

  down do
    puts '002_add_next_block_hash.rb DOWN'
    alter_table(:blocks) do
      drop_column :nextBlockHash
    end
  end
end
