class CreateKhataReceipts < ActiveRecord::Migration[7.2]
  def change
    create_table :khata_receipts, id: :integer do |t|
      t.integer :customer_id, null: false
      t.string :receipt_number
      t.date :received_on, null: false
      t.integer :amount_cents, null: false, default: 0
      t.string :payment_method
      t.string :note
      t.integer :balance_before_cents, null: false, default: 0
      t.integer :balance_after_cents, null: false, default: 0
      t.integer :deposited_to_date_cents, null: false, default: 0
      t.timestamps
    end
    add_index :khata_receipts, :customer_id
    add_index :khata_receipts, :receipt_number, unique: true
    add_foreign_key :khata_receipts, :customers

    add_column :payments, :khata_receipt_id, :integer
    add_index :payments, :khata_receipt_id
    add_column :ledger_entries, :khata_receipt_id, :integer
    add_index :ledger_entries, :khata_receipt_id
  end
end
