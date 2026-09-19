class CreateLedgerEntries < ActiveRecord::Migration[5.0]
  def change
    create_table :ledger_entries do |t|
      t.references :customer, foreign_key: true, null: false
      t.date :entry_date, null: false
      t.string :kind, null: false
      t.integer :amount_cents, null: false, default: 0
      t.string :note

      t.timestamps
    end

    add_index :ledger_entries, [:customer_id, :entry_date]
  end
end
