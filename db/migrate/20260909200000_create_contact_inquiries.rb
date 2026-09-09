class CreateContactInquiries < ActiveRecord::Migration[7.2]
  def change
    create_table :contact_inquiries do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :phone
      t.string :subject
      t.text :message, null: false
      t.string :status, default: 'new', null: false
      t.timestamps
    end
    add_index :contact_inquiries, :created_at
    add_index :contact_inquiries, :email
  end
end
