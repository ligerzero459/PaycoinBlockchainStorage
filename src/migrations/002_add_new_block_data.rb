require 'json'

require './src/models/block'
require './src/models/raw_block'

Sequel.migration do
  up do
    alter_table(:blocks) do
      add_column :blockSize, Fixnum
      add_column :merkleRoot, String
      add_column :difficulty, Float
    end

    Block.set_dataset(:blocks)

    raw_blocks = RawBlock.all
    raw_blocks.each do |raw_block|
      block_info = raw_block.raw
      block_json = JSON.parse(block_info)
      Block[:height => raw_block.height].update(
          :blockSize => block_json.fetch("size").to_i,
          :merkleRoot => block_json.fetch("merkleroot"),
          :difficulty => block_json.fetch("difficulty").to_f
      )
    end
  end

  down do
    alter_table(:blocks) do
      drop_column :blockSize
      drop_column :merkleRoot
      drop_column :difficulty
    end
  end
end