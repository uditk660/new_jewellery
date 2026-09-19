class AddArchivedToJewelryItems < ActiveRecord::Migration[7.2]
  def change
    add_column :jewelry_items, :archived, :boolean, null: false, default: false
    add_index :jewelry_items, :archived
  end
end
