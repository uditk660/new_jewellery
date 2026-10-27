class AddKindToKhataReceipts < ActiveRecord::Migration[7.2]
  def change
    add_column :khata_receipts, :kind, :string, null: false, default: 'credit'
  end
end
