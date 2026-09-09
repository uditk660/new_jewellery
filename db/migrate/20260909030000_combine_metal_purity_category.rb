class CombineMetalPurityCategory < ActiveRecord::Migration[7.2]
  def change
    change_table :metals do |t|
      t.string :code
      t.string :hsn_code
      t.string :colour
      t.text :notes
      t.integer :display_order, default: 0
      t.boolean :bis_mandatory, default: false
    end

    change_table :purities do |t|
      t.string :fineness
      t.string :hallmark_standard
      t.decimal :wastage_percent, precision: 8, scale: 4
      t.decimal :making_charge_percent, precision: 8, scale: 4
      t.integer :position, default: 0
    end

    change_table :jewellery_categories do |t|
      t.string :description
      t.string :hsn_code
      t.string :gender
      t.decimal :default_making_charge_percent, precision: 8, scale: 4
      t.integer :position, default: 0
    end

    add_index :metals, :code, unique: true
    add_index :purities, [:metal_id, :name], unique: true, name: 'index_purities_on_metal_id_and_name'
    add_index :jewellery_categories, [:metal_id, :name], unique: true, name: 'index_jewellery_categories_on_metal_id_and_name'
  end
end
