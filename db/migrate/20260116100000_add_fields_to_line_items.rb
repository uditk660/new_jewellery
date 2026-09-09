class AddFieldsToLineItems < ActiveRecord::Migration[5.0]
  def change
    add_column :line_items, :hsn, :string
    add_column :line_items, :gross_weight, :decimal, precision: 10, scale: 2, default: 0.0
    add_column :line_items, :net_weight, :decimal, precision: 10, scale: 2, default: 0.0
    add_column :line_items, :making_charge, :decimal, precision: 12, scale: 2, default: 0.0
  end
end
