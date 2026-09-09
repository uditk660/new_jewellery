class AddShareTokenToOrders < ActiveRecord::Migration[7.2]
  def up
    add_column :orders, :share_token, :string
    add_index :orders, :share_token, unique: true

    reversible do |dir|
      dir.up do
        say_with_time 'issue share tokens for existing bills' do
          Order.reset_column_information
          Order.find_each do |order|
            next if order.share_token.present?

            token = nil
            8.times do
              token = SecureRandom.hex(16)
              break unless Order.exists?(share_token: token)
            end
            order.update_column(:share_token, token)
          end
        end
      end
    end
  end

  def down
    remove_index :orders, :share_token
    remove_column :orders, :share_token
  end
end
