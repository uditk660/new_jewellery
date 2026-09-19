class MetalStock < ActiveRecord::Base
  MOVEMENT_TYPES = %w[in out adjustment return manual].freeze
  LIGHT_GRAMS = 100

  belongs_to :metal
  belongs_to :store
  has_many :metal_stock_movements, dependent: :restrict_with_error

  validates :metal_id, uniqueness: { scope: :store_id, message: 'already has a card at this store' }
  validates :available_grams, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :price_cents_per_gram, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def price_per_gram
    price_cents_per_gram.to_f / 100.0
  end

  def price_per_gram=(dollars)
    self.price_cents_per_gram = (dollars.to_s.gsub(',', '').to_f * 100).round
  end

  def stock_value
    (available_grams.to_i * price_per_gram).round(2)
  end

  def empty?
    available_grams.to_i <= 0
  end

  def light?
    grams = available_grams.to_i
    grams.positive? && grams <= LIGHT_GRAMS
  end

  def signed_delta(change_grams, movement_type)
    grams = change_grams.to_i
    case movement_type.to_s
    when 'out' then -grams.abs
    when 'in', 'return' then grams.abs
    else grams
    end
  end

  def adjust!(change_grams, movement_type: 'adjustment', note: nil)
    type = movement_type.to_s
    type = 'adjustment' unless MOVEMENT_TYPES.include?(type)
    delta = signed_delta(change_grams, type)

    transaction do
      next_grams = available_grams.to_i + delta
      if next_grams.negative?
        errors.add(:available_grams, 'cannot go below 0 g')
        raise ActiveRecord::RecordInvalid, self
      end
      self.available_grams = next_grams
      save!
      metal_stock_movements.create!(
        change_grams: delta,
        movement_type: type == 'manual' ? 'adjustment' : type,
        note: note.to_s.strip.presence
      )
    end
  end
end
