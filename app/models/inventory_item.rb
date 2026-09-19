class InventoryItem < ActiveRecord::Base
  MOVEMENT_TYPES = %w[in out adjustment return].freeze

  belongs_to :jewelry_item
  has_many :stock_movements, dependent: :restrict_with_error

  validates :jewelry_item_id, uniqueness: { message: 'is already on the stock book' }
  validates :available_grams, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :location, length: { maximum: 80 }, allow_blank: true

  before_validation :normalize_location

  def location_label
    location.presence || 'Main tray'
  end

  def empty?
    available_grams.to_i <= 0
  end

  def light?
    piece = jewelry_item
    grams = available_grams.to_i
    return false if grams <= 0
    return grams <= 10 unless piece && piece.weight_grams.to_f.positive?

    grams < piece.weight_grams.to_f.round
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
      stock_movements.create!(
        change_grams: delta,
        movement_type: type,
        note: note.to_s.strip.presence
      )
    end
  end

  private

  def normalize_location
    self.location = location.to_s.strip.presence
  end
end
