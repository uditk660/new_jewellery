# Full house book for a date window: counter activity plus standing tray, vault and khata.
class HouseReport
  attr_reader :book, :house_name

  def self.for(params, returns: [], house_name: 'The house')
    new(ProfitLoss.for(params, returns: returns), returns: returns, house_name: house_name)
  end

  def initialize(book, returns: [], house_name: 'The house')
    @book = book
    @return_records = Array(returns)
    @house_name = house_name.to_s.presence || 'The house'
  end

  delegate :from, :to, :window, :label, :metal_id, :metal_filter, :bill_count, :pieces, :grams,
           :metal, :making, :extra, :charges, :discount, :taxable, :gst, :cgst, :sgst, :bill_total,
           :house_result, :cash_refunds, :receipts, :outstanding, :paid_bills, :open_bills,
           :margin_percent, :mix, :by_metal, :statement_lines, :series, :series_max, :bills,
           to: :book

  def generated_at
    Time.zone.now
  end

  def tray
    @tray ||= begin
      items = JewelryItem.kept.includes(:metal, :purity).to_a
      live = items.select { |item| item.quantity.to_i.positive? }
      {
        live_pcs: live.sum { |item| item.quantity.to_i },
        pieces: items.size,
        grams: live.sum { |item| item.weight_grams.to_f * item.quantity.to_i },
        value: live.sum { |item| item.stock_amount.to_f },
        stock_out: items.count { |item| item.quantity.to_i <= 0 },
        locked: items.count(&:sale_locked?),
        light: live.select { |item| item.quantity.to_i <= 2 }.first(6)
      }
    end
  end

  def vault
    @vault ||= begin
      rows = MetalStock.includes(:metal, :store).to_a
      {
        grams: rows.sum { |row| row.available_grams.to_i },
        value: rows.sum(&:stock_value),
        cards: rows.size,
        stores: rows.map(&:store_id).uniq.size,
        light: rows.select(&:light?),
        empty: rows.select(&:empty?)
      }
    end
  end

  def hallmarks
    @hallmarks ||= begin
      grams = if Purity.column_names.include?('available_grams')
                Purity.sum(:available_grams).to_f
              else
                0.0
              end
      { grams: grams, count: Purity.count }
    end
  end

  def khata
    @khata ||= begin
      unless Customer.column_names.include?('balance_cents')
        return { receivable: 0.0, advances: 0.0, due: 0, advance: 0, clients: Customer.count }
      end
      {
        receivable: Customer.where('balance_cents > 0').sum(:balance_cents).to_i / 100.0,
        advances: Customer.where('balance_cents < 0').sum(:balance_cents).to_i.abs / 100.0,
        due: Customer.where('balance_cents > 0').count,
        advance: Customer.where('balance_cents < 0').count,
        clients: Customer.count
      }
    end
  end

  def new_clients
    @new_clients ||= Customer.where(created_at: book.from.beginning_of_day..book.to.end_of_day).count
  end

  def board
    @board ||= Metal.includes(:purities).ordered.map do |metal_row|
      {
        id: metal_row.id,
        name: metal_row.name,
        colour: metal_row.chip_colour,
        locked: metal_row.rate_board_locked?,
        purities: metal_row.purities.ordered.map do |purity|
          {
            name: purity.name,
            label: purity.hallmark_label,
            rate: purity.updated_price.to_f,
            grams: purity.respond_to?(:available_grams) ? purity.available_grams.to_f : 0.0
          }
        end
      }
    end
  end

  def by_category
    groups = {}
    each_line do |item, jewelry|
      category = jewelry&.jewellery_category
      key = category&.id || 0
      groups[key] ||= {
        name: category&.display_name.presence || 'Uncategorised',
        metal: jewelry&.metal&.name,
        pcs: 0,
        grams: 0.0,
        making: 0.0,
        amount: 0.0
      }
      groups[key][:pcs] += item.quantity.to_i
      groups[key][:grams] += item.net_weight.to_f * item.quantity.to_i
      groups[key][:making] += item.making_charge.to_f
      groups[key][:amount] += item.line_amount.to_f
    end
    groups.values.sort_by { |row| -row[:amount] }
  end

  def top_pieces
    groups = {}
    each_line do |item, jewelry|
      key = jewelry&.id || 0
      groups[key] ||= {
        item: jewelry,
        name: jewelry&.name.presence || 'Piece',
        sku: jewelry&.sku,
        metal: jewelry&.metal&.name,
        purity: jewelry&.purity&.name,
        pcs: 0,
        grams: 0.0,
        making: 0.0,
        amount: 0.0
      }
      groups[key][:pcs] += item.quantity.to_i
      groups[key][:grams] += item.net_weight.to_f * item.quantity.to_i
      groups[key][:making] += item.making_charge.to_f
      groups[key][:amount] += item.line_amount.to_f
    end
    groups.values.sort_by { |row| -row[:amount] }.first(8)
  end

  def top_clients
    groups = {}
    book.slices.each do |row|
      client = row[:client]
      key = client&.id || 0
      groups[key] ||= {
        client: client,
        name: client&.full_name.presence || 'Walk-in',
        ref: client&.try(:client_ref),
        bills: 0,
        grams: 0.0,
        total: 0.0,
        house: 0.0
      }
      groups[key][:bills] += 1
      groups[key][:grams] += row[:grams]
      groups[key][:total] += row[:total]
      groups[key][:house] += row[:house]
    end
    groups.values.sort_by { |row| -row[:total] }.first(8)
  end

  def payments
    @payments ||= begin
      rel = Payment.where(created_at: book.from.beginning_of_day..book.to.end_of_day)
      grouped = rel.group("COALESCE(NULLIF(payment_method, ''), 'Unnoted')").sum(:amount_cents)
      {
        count: rel.count,
        total: rel.sum(:amount_cents).to_i / 100.0,
        methods: grouped.map { |name, cents| { name: name, amount: cents.to_i / 100.0 } }.sort_by { |row| -row[:amount] }
      }
    end
  end

  def returns
    @returns ||= begin
      rows = @return_records.map { |record| record.respond_to?(:to_h) ? record.to_h.stringify_keys : {} }
      in_window = rows.select do |row|
        at = parse_time(row['created_at'])
        at && at.to_date.between?(book.from, book.to)
      end
      cash = in_window.select { |row| row['action'].to_s == 'cash' }
      exchange = in_window.select { |row| row['action'].to_s == 'exchange' }
      {
        count: in_window.size,
        cash: cash.size,
        exchange: exchange.size,
        cash_amount: cash.sum { |row| row['amount'].to_f }
      }
    end
  end

  def due_clients
    return [] unless Customer.column_names.include?('balance_cents')

    Customer.where('balance_cents > 0').order(balance_cents: :desc).limit(6).to_a
  end

  private

  def each_line
    book.orders.each do |order|
      order.line_items.each do |item|
        jewelry = item.jewelry_item
        next if book.metal_id.present? && jewelry&.metal_id.to_s != book.metal_id.to_s

        yield item, jewelry
      end
    end
  end

  def parse_time(value)
    return value if value.respond_to?(:to_date)

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
