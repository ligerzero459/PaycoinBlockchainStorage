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

    Block[:height => 0].update(
        :blockSize => 217,
        :merkleRoot => '1552f748afb7ff4e04776652c5a17d4073e60b7004e9bca639a99edb82aeb1a0',
        :difficulty => 0.00024414
    )

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
