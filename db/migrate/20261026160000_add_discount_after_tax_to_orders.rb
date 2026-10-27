# Discount and extra charges now apply to the total after CGST + SGST.
# Settled bills keep the figures they were paid on (discount before tax);
# pending and new bills use the after-tax rule.
class AddDiscountAfterTaxToOrders < ActiveRecord::Migration[7.2]
  def up
    add_column :orders, :discount_after_tax, :boolean, null: false, default: false
    execute "UPDATE orders SET discount_after_tax = TRUE WHERE status = 'pending'"
    change_column_default :orders, :discount_after_tax, from: false, to: true
  end

  def down
    remove_column :orders, :discount_after_tax
  end
end
