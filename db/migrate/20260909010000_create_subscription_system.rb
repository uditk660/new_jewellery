class CreateSubscriptionSystem < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :shop_name, :string
    add_column :users, :full_name, :string
    add_column :users, :phone, :string

    create_table :employees, id: :integer do |t|
      t.string :email, null: false, default: ''
      t.string :encrypted_password, null: false, default: ''
      t.string :name
      t.datetime :remember_created_at
      t.timestamps
    end
    add_index :employees, :email, unique: true

    create_table :plans, id: :integer do |t|
      t.string :name, null: false
      t.string :tagline
      t.text :description
      t.integer :price_cents, null: false, default: 0
      t.text :features
      t.boolean :active, null: false, default: true
      t.boolean :featured, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :subscriptions, id: :integer do |t|
      t.integer :user_id, null: false
      t.integer :plan_id, null: false
      t.string :status, null: false, default: 'pending'
      t.string :source, null: false, default: 'user_request'
      t.datetime :starts_at
      t.datetime :ends_at
      t.datetime :requested_at
      t.datetime :reviewed_at
      t.integer :reviewed_by_id
      t.text :decision_note
      t.timestamps
    end
    add_index :subscriptions, :user_id
    add_index :subscriptions, :plan_id
    add_index :subscriptions, :status
    add_index :subscriptions, :reviewed_by_id

    create_table :audit_logs, id: :integer do |t|
      t.integer :employee_id
      t.integer :user_id
      t.integer :subscription_id
      t.integer :plan_id
      t.string :action, null: false
      t.text :notes
      t.string :ip_address
      t.timestamps
    end
    add_index :audit_logs, :employee_id
    add_index :audit_logs, :created_at
  end
end
