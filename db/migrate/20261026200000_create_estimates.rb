class CreateEstimates < ActiveRecord::Migration[7.2]
  def change
    create_table :estimates, id: :integer do |t|
      t.integer :estimate_no, null: false
      t.date :estimate_date, null: false
      t.integer :customer_id
      t.string :party_name, null: false
      t.string :party_place
      t.string :party_phone
      t.text :items
      t.text :settlements
      t.string :prev_ref
      t.integer :prev_fine_mg, null: false, default: 0
      t.bigint :prev_amount_cents, null: false, default: 0
      t.integer :net_mg, null: false, default: 0
      t.integer :fine_mg, null: false, default: 0
      t.bigint :amount_cents, null: false, default: 0
      t.integer :closing_fine_mg, null: false, default: 0
      t.bigint :closing_amount_cents, null: false, default: 0
      t.string :note
      t.timestamps
    end
    add_index :estimates, :estimate_no, unique: true
    add_index :estimates, :customer_id
    add_index :estimates, :estimate_date
  end
end
