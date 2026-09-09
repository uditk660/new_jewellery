class Plan < ActiveRecord::Base
  has_many :subscriptions, dependent: :restrict_with_error

  validates :name, presence: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true).order(:position, :price_cents) }

  def feature_list
    (features.presence || '').split(/\r?\n/).map(&:strip).reject(&:blank?)
  end

  def price_rupees
    price_cents.to_i / 100.0
  end
end
