# A rough estimate (kaccha bill) kept in two columns: fine gold in milligrams and
# money in paise. It is a working slip for the client and does not touch stock,
# bills or the khata.
class Estimate < ActiveRecord::Base
  SETTLEMENT_KINDS = {
    'metal' => 'Metal received',
    'bhav' => 'Gold bhav',
    'cash' => 'Receipt cash'
  }.freeze
  LABOUR_ON = %w[pc g].freeze
  MAX_MG = 100_000_000
  MAX_CENTS = 100_000_000_000

  belongs_to :customer, optional: true

  LABELS = { 'party_name' => 'Name on slip', 'party_place' => 'Place', 'party_phone' => 'Mobile',
             'prev_ref' => 'Balance reference', 'estimate_date' => 'Date' }.freeze

  def self.human_attribute_name(attr, options = {})
    LABELS[attr.to_s] || super
  end

  serialize :items, coder: JSON
  serialize :settlements, coder: JSON

  validates :estimate_no, presence: true, uniqueness: true
  validates :estimate_date, presence: true
  validates :party_name, presence: true, length: { maximum: 120 }
  validates :party_place, :party_phone, :prev_ref, length: { maximum: 80 }, allow_blank: true
  validates :note, length: { maximum: 200 }, allow_blank: true
  validate :has_lines
  validate :sane_numbers

  before_validation :assign_number, on: :create
  before_validation :compute

  def self.next_number
    (maximum(:estimate_no) || 0) + 1
  end

  # Last closing balance for this client, to carry forward as "Bal." on the next estimate.
  def self.carry_forward_for(customer_id)
    last = where(customer_id: customer_id).order(estimate_date: :desc, estimate_no: :desc).first
    return nil unless last

    {
      ref: "#{last.estimate_no}-#{last.estimate_date.strftime('%d/%m/%y')}",
      fine: mg_to_g(last.closing_fine_mg),
      amount: Paise.rupees(last.closing_amount_cents)
    }
  end

  def self.mg_from(value)
    (Paise.dec!(value) * 1000).round(0, BigDecimal::ROUND_HALF_UP).to_i
  end

  def self.mg_to_g(mg)
    mg.to_i / 1000.0
  end

  def self.percent(value)
    Paise.round2(value)
  end

  # Fine gold in a weight at a tunch or touch, rounded half-up to the milligram.
  def self.fine_mg(weight_mg, percent)
    (BigDecimal(weight_mg.to_i) * Paise.dec!(percent) / 100).round(0, BigDecimal::ROUND_HALF_UP).to_i
  end

  # Bhav is quoted per 10 g, as on the shop board.
  def self.bhav_cents(fine_mg, rate_per_10g)
    (BigDecimal(fine_mg.to_i) * Paise.dec!(rate_per_10g) * 100 / 10_000).round(0, BigDecimal::ROUND_HALF_UP).to_i
  end

  def item_rows
    Array(items)
  end

  def settlement_rows
    Array(settlements)
  end

  def pcs
    item_rows.sum { |row| row['pcs'].to_i }
  end

  def net_total_fine_mg
    fine_mg.to_i + prev_fine_mg.to_i
  end

  def net_total_amount_cents
    amount_cents.to_i + prev_amount_cents.to_i
  end

  def number_label
    estimate_no.to_s
  end

  def settled?
    closing_fine_mg.to_i.zero? && closing_amount_cents.to_i.zero?
  end

  # Raw rows from the form, cleaned to the stored shape. Computed fields are filled by #compute.
  def assign_rows(raw_items, raw_settlements)
    self.items = Array(raw_items).filter_map do |row|
      row = row.to_h.stringify_keys
      desc = row['description'].to_s.strip
      next if desc.blank? && row['net_weight'].to_s.strip.blank?

      {
        'description' => desc.first(80),
        'jewelry_item_id' => row['jewelry_item_id'].presence&.to_i,
        'pcs' => row['pcs'].to_s.strip.presence || '0',
        'net_weight' => row['net_weight'].to_s.strip,
        'tunch' => row['tunch'].to_s.strip,
        'labour' => row['labour'].to_s.strip.presence || '0',
        'labour_on' => LABOUR_ON.include?(row['labour_on'].to_s) ? row['labour_on'].to_s : 'pc'
      }
    end
    self.settlements = Array(raw_settlements).filter_map do |row|
      row = row.to_h.stringify_keys
      kind = row['kind'].to_s
      next unless SETTLEMENT_KINDS.key?(kind)

      {
        'kind' => kind,
        'description' => row['description'].to_s.strip.first(60),
        'weight' => row['weight'].to_s.strip,
        'touch' => row['touch'].to_s.strip,
        'fine' => row['fine'].to_s.strip,
        'rate' => row['rate'].to_s.strip,
        'amount' => row['amount'].to_s.strip
      }
    end
  end

  private

  def number?(value, allow_negative: false)
    parsed = Paise.dec(value)
    return false if parsed.nil?

    allow_negative || parsed >= 0
  end

  def assign_number
    self.estimate_no ||= self.class.next_number
  end

  def compute
    @bad_numbers = []
    net = fine = amount = 0
    self.items = item_rows.each_with_index.map do |row, i|
      n = i + 1
      @bad_numbers << "Piece #{n}: pieces must be a whole number." unless row['pcs'].to_s.match?(/\A\d+\z/)
      @bad_numbers << "Piece #{n}: enter the net weight in grams." unless number?(row['net_weight'])
      @bad_numbers << "Piece #{n}: tunch must be between 0 and 100." unless number?(row['tunch']) && Paise.dec(row['tunch']) <= 100
      @bad_numbers << "Piece #{n}: labour must be a plain number." unless number?(row['labour'])
      row_net = self.class.mg_from(row['net_weight'])
      tunch = self.class.percent(row['tunch'])
      row_fine = self.class.fine_mg(row_net, tunch)
      labour = Paise.from_rupees(row['labour'])
      row_amount = row['labour_on'] == 'g' ? (BigDecimal(row_net) * labour / 1000).round(0, BigDecimal::ROUND_HALF_UP).to_i : labour * row['pcs'].to_i
      net += row_net
      fine += row_fine
      amount += row_amount
      row.merge('net_mg' => row_net, 'fine_mg' => row_fine, 'amount_cents' => row_amount, 'tunch' => format('%.2f', tunch))
    end
    self.net_mg = net
    self.fine_mg = fine
    self.amount_cents = amount

    running_fine = fine + prev_fine_mg.to_i
    running_amount = amount + prev_amount_cents.to_i
    self.settlements = settlement_rows.each_with_index.map do |row, i|
      n = i + 1
      fine_effect = amount_effect = 0
      case row['kind']
      when 'metal'
        @bad_numbers << "Settlement #{n}: metal weight must be a plain number." unless number?(row['weight'])
        @bad_numbers << "Settlement #{n}: touch must be between 0 and 100." unless number?(row['touch']) && Paise.dec(row['touch']) <= 100
        weight = self.class.mg_from(row['weight'])
        fine_effect = -self.class.fine_mg(weight, self.class.percent(row['touch']))
        row = row.merge('weight_mg' => weight, 'touch' => format('%.2f', self.class.percent(row['touch'])))
      when 'bhav'
        @bad_numbers << "Settlement #{n}: fine to convert must be a number." unless number?(row['fine'], allow_negative: true)
        @bad_numbers << "Settlement #{n}: bhav must be a plain number." unless number?(row['rate'])
        converted = self.class.mg_from(row['fine'])
        fine_effect = -converted
        amount_effect = self.class.bhav_cents(converted, row['rate'])
        row = row.merge('converted_mg' => converted, 'rate' => format('%.2f', Paise.round2(row['rate'])))
      when 'cash'
        @bad_numbers << "Settlement #{n}: cash must be a plain number." unless number?(row['amount'])
        amount_effect = -Paise.from_rupees(row['amount'])
      end
      running_fine += fine_effect
      running_amount += amount_effect
      row.merge('fine_mg' => fine_effect, 'amount_cents' => amount_effect)
    end
    self.closing_fine_mg = running_fine
    self.closing_amount_cents = running_amount
  end

  def has_lines
    return if item_rows.any? || settlement_rows.any?

    errors.add(:base, 'Add at least one piece or settlement line.')
  end

  def sane_numbers
    Array(@bad_numbers).uniq.each { |msg| errors.add(:base, msg) }
    values = [net_mg, fine_mg, closing_fine_mg, prev_fine_mg].map { |v| v.to_i.abs }
    errors.add(:base, 'A weight is larger than an estimate can hold.') if values.any? { |v| v > MAX_MG }
    money = [amount_cents, closing_amount_cents, prev_amount_cents].map { |v| v.to_i.abs }
    errors.add(:base, 'An amount is larger than an estimate can hold.') if money.any? { |v| v > MAX_CENTS }
  end
end
