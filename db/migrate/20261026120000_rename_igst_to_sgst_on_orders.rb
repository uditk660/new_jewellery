class RenameIgstToSgstOnOrders < ActiveRecord::Migration[7.2]
  def change
    rename_column :orders, :igst_rate, :sgst_rate
    rename_column :orders, :igst_cents, :sgst_cents
  end
end
