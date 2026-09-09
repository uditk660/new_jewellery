class CreateShopProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :shop_profiles, id: :integer do |t|
      t.integer :user_id, null: false
      t.string :shop_name
      t.string :legal_name
      t.string :owner_name
      t.string :tagline
      t.string :phone
      t.string :alternate_phone
      t.string :whatsapp
      t.string :email
      t.string :website
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :state
      t.string :pincode
      t.string :country, default: 'India'
      t.string :gstin
      t.string :pan
      t.string :registration_number
      t.string :cin
      t.string :bis_hallmark_licence
      t.string :hallmark_center
      t.string :hallmark_center_code
      t.string :jeweller_type
      t.string :association_membership
      t.integer :established_year
      t.string :working_hours
      t.string :bank_name
      t.string :account_holder
      t.string :account_number
      t.string :ifsc
      t.text :invoice_declaration
      t.datetime :completed_at
      t.timestamps
    end
    add_index :shop_profiles, :user_id, unique: true
  end
end
