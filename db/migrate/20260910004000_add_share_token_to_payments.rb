class AddShareTokenToPayments < ActiveRecord::Migration[7.2]
  def up
    add_column :payments, :share_token, :string
    add_index :payments, :share_token, unique: true

    say_with_time 'issue share tokens for existing receipts' do
      Payment.reset_column_information
      Payment.find_each do |payment|
        next if payment.share_token.present?

        token = nil
        8.times do
          token = SecureRandom.hex(16)
          break unless Payment.exists?(share_token: token)
        end
        payment.update_column(:share_token, token)
      end
    end
  end

  def down
    remove_index :payments, :share_token
    remove_column :payments, :share_token
  end
end
