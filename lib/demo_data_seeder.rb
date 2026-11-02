# Idempotent demo rows for development: 100 metals, hallmarks (purities),
# categories, catalogue pieces, clients, stores, vault lines and daily rates.
# Re-run safely — records are keyed by SEED-* codes / phones / SKUs.
class DemoDataSeeder
  PREFIX = 'SEED'.freeze
  PIECE_NAMES = %w[Ring Band Chain Bangle Pendant Earring Necklace Bracelet Anklet Nosepin Mangalsutra].freeze
  METAL_COLOURS = %w[#c9a227 #c5cdd8 #9aa3b2 #b76e79 #d4af37 #a8a9ad].freeze

  class << self
    def seed!(count: 100)
      new(count: count).run
    end
  end

  def initialize(count: 100)
    @count = count.to_i.clamp(1, 500)
    @stats = Hash.new(0)
  end

  def run
    puts "DemoDataSeeder: ensuring #{@count} rows per master (prefix #{PREFIX})…"
    metals = ensure_metals
    purities = ensure_purities(metals)
    categories = ensure_categories(metals)
    ensure_stores
    ensure_metal_stocks(metals)
    ensure_rates
    ensure_customers
    ensure_pieces(metals, purities, categories)
    print_summary
    @stats
  end

  private

  def print_summary
    totals = {
      metals: Metal.count,
      purities: Purity.count,
      jewellery_categories: JewelleryCategory.count,
      jewelry_items: JewelryItem.count,
      customers: Customer.count,
      stores: Store.count,
      metal_stocks: MetalStock.count,
      rates: Rate.count
    }
    puts 'Done:'
    @stats.sort.each { |k, v| puts "  #{k}: +#{v} new (#{totals[k] || '?'} in database)" }
  end

  def bump(key)
    @stats[key] += 1
  end

  def ensure_metals
    metals = []
    @count.times do |i|
      n = i + 1
      code = format('%s-MET-%03d', PREFIX, n)
      metal = Metal.find_by(code: code)
      unless metal
        metal = Metal.create!(
          name: "#{PREFIX} Metal #{n}",
          code: code,
          base_unit: (n.even? ? 'gram' : 'carat'),
          hsn_code: format('7113%02d', n % 100),
          colour: METAL_COLOURS[n % METAL_COLOURS.size],
          display_order: n,
          active: true,
          bis_mandatory: (n % 10).zero?
        )
        bump(:metals)
      end
      metals << metal
    end
    metals
  end

  def ensure_purities(metals)
    purities = []
    @count.times do |i|
      n = i + 1
      metal = metals[i]
      name = format('%s Hallmark %03d', PREFIX, n)
      purity = metal.purities.find_by(name: name)
      unless purity
        purity = metal.purities.create!(
          name: name,
          purity_percent: [91.6, 75.0, 99.9, 83.5, 58.5][n % 5],
          fineness: format('916%03d', n % 1000),
          hallmark_standard: (n.even? ? 'BIS' : 'None'),
          updated_price: BigDecimal('5500') + n * 15,
          wastage_percent: (n % 7),
          making_charge_percent: 10 + (n % 12),
          available_grams: 25_000,
          position: n,
          active: true
        )
        bump(:purities)
      else
        purity.update!(available_grams: [purity.available_grams.to_d, 25_000].max) if purity.available_grams.to_d < 5000
      end
      purities << purity
    end
    purities
  end

  def ensure_categories(metals)
    categories = []
    @count.times do |i|
      n = i + 1
      metal = metals[i]
      name = format('%s Category %03d', PREFIX, n)
      cat = metal.jewellery_categories.find_by(name: name)
      unless cat
        cat = metal.jewellery_categories.create!(
          name: name,
          gender: JewelleryCategory::GENDERS[n % JewelleryCategory::GENDERS.size],
          hsn_code: format('7113%02d', (n + 17) % 100),
          default_making_charge_percent: 8 + (n % 15),
          position: n,
          active: true,
          description: 'Demo catalogue grouping for the atelier.'
        )
        bump(:jewellery_categories)
      end
      categories << cat
    end
    categories
  end

  def ensure_stores
    @count.times do |i|
      n = i + 1
      name = format('%s Store %03d', PREFIX, n)
      next if Store.exists?(name: name)

      Store.create!(name: name, location: "Demo vault · Block #{n}")
      bump(:stores)
    end
  end

  def ensure_metal_stocks(metals)
    stores = Store.where('name LIKE ?', "#{PREFIX} Store %").order(:id).limit(@count).to_a
    return if stores.empty?

    @count.times do |i|
      n = i + 1
      metal = metals[i]
      store = stores[i % stores.size]
      ms = MetalStock.find_by(metal_id: metal.id, store_id: store.id)
      next if ms

      MetalStock.create!(
        metal: metal,
        store: store,
        available_grams: 5000 + (n * 37),
        price_cents_per_gram: 550_000 + (n * 100)
      )
      bump(:metal_stocks)
    end
  end

  def ensure_rates
    base = Time.zone.today
    @count.times do |i|
      n = i + 1
      metal_type = format('%s-Gold-%03d', PREFIX, n)
      date = base - (n % 90).days
      next if Rate.exists?(date: date, metal_type: metal_type)

      Rate.create!(
        date: date,
        metal_type: metal_type,
        price_cents_per_gram: 520_000 + (n * 50)
      )
      bump(:rates)
    end
  end

  def ensure_customers
    @count.times do |i|
      n = i + 1
      digits = format('%010d', 9_000_000_000 + n)
      phone = "+91#{digits[-10..]}"
      customer = Customer.find_by(phone: phone) || Customer.find_by(phone: digits)
      next if customer

      Customer.create!(
        first_name: "#{PREFIX} Client",
        last_name: format('%03d', n),
        phone: digits,
        email: format('%s.client.%03d@demo.strucxil.local', PREFIX.downcase, n),
        address: "#{n} Demo Lane, Mumbai",
        gst_number: n.even? ? format('27AAAAA%04d1Z5', n) : nil
      )
      bump(:customers)
    end
  end

  def ensure_pieces(metals, purities, categories)
    @count.times do |i|
      n = i + 1
      sku = format('%s-PIECE-%03d', PREFIX, n)
      next if JewelryItem.exists?(sku: sku)

      metal = metals[i]
      purity = purities[i]
      category = categories[i]
      weight = BigDecimal(format('%.2f', 1.5 + (n % 45) / 10.0))
      qty = 1 + (n % 4)
      piece = PIECE_NAMES[n % PIECE_NAMES.size]

      JewelryItem.create!(
        sku: sku,
        name: format('%s %s %03d', PREFIX, piece, n),
        description: 'Registered for demo sales and paging tests.',
        metal: metal,
        purity: purity,
        jewellery_category: category,
        weight_grams: weight,
        quantity: qty
      )
      bump(:jewelry_items)
    end
  end
end
