class AddAvailableGramsToPurities < ActiveRecord::Migration[7.2]
  def change
    add_column :purities, :available_grams, :decimal, precision: 12, scale: 2, default: 0, null: false
  end
end
