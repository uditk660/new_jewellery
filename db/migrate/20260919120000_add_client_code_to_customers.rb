class AddClientCodeToCustomers < ActiveRecord::Migration[5.0]
  def up
    add_column :customers, :client_code, :string
    add_index :customers, :client_code, unique: true

    prefix = house_prefix
    alphabet = ('A'..'Z').to_a + ('0'..'9').to_a
    say_with_time 'assign house client numbers' do
      Customer.reset_column_information
      Customer.find_each do |customer|
        next if customer.client_code.present?
        code = nil
        12.times do
          token = 10.times.map { alphabet[SecureRandom.random_number(alphabet.length)] }.join
          candidate = "#{prefix}-#{token}"
          unless Customer.where(client_code: candidate).exists?
            code = candidate
            break
          end
        end
        customer.update_columns(client_code: code || "#{prefix}-#{SecureRandom.hex(5).upcase}")
      end
    end
  end

  def down
    remove_index :customers, :client_code
    remove_column :customers, :client_code
  end

  private

  def house_prefix
    name = nil
    name = ShopProfile.order(:id).first&.shop_name if defined?(ShopProfile) && ActiveRecord::Base.connection.data_source_exists?('shop_profiles')
    name = User.order(:id).first&.shop_name if name.blank? && defined?(User)
    words = name.to_s.upcase.scan(/[A-Z0-9]+/).reject { |w| %w[AND THE OF FOR A AN].include?(w) }
    letters = words.map { |w| w[0] }.join
    letters = name.to_s.upcase.gsub(/[^A-Z0-9]/, '') if letters.length < 2
    (letters[0, 3].presence || 'HS')
  end
end
