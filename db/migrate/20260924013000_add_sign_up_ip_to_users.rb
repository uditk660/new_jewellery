class AddSignUpIpToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :sign_up_ip, :string
  end
end
