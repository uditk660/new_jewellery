namespace :demo_data do
  # desc 'Add 100 demo metals, hallmarks, categories, pieces, clients, stores, vault & rates (idempotent). COUNT=50'
  # task seed: :environment do
  #   require Rails.root.join('lib/demo_data_seeder')
  #   DemoDataSeeder.seed!(count: ENV.fetch('COUNT', 100).to_i)
  # end

  # desc 'Remove SEED-* demo catalogue rows'
  # task clear: :environment do
  #   prefix = DemoDataSeeder::PREFIX
  #   require Rails.root.join('lib/demo_data_seeder')
  #   puts "Clearing #{prefix} demo data…"

  #   piece_ids = JewelryItem.where('sku LIKE ?', "#{prefix}-PIECE-%").pluck(:id)
  #   JewelryItem.where(id: piece_ids).destroy_all
  #   puts "  jewelry_items: #{piece_ids.size}"

  #   Customer.where('email LIKE ?', "#{prefix.downcase}.client.%@demo.strucxil.local").delete_all

  #   Rate.where('metal_type LIKE ?', "#{prefix}-%").delete_all
  #   MetalStock.joins(:metal).where('metals.code LIKE ?', "#{prefix}-MET-%").delete_all
  #   Store.where('name LIKE ?', "#{prefix} Store %").delete_all

  #   Metal.where('code LIKE ?', "#{prefix}-MET-%").find_each do |metal|
  #     metal.purities.where('name LIKE ?', "#{prefix} %").delete_all
  #     metal.jewellery_categories.where('name LIKE ?', "#{prefix} %").delete_all
  #     metal.destroy!
  #   rescue ActiveRecord::RecordNotDestroyed => e
  #     warn "  metal #{metal.code}: #{e.record.errors.full_messages.to_sentence}"
  #   end

  #   puts 'Clear finished.'
  # end
end
