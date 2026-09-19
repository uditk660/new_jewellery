module ApplicationHelper
  include MoneyHelper
  # Some older/newer Rails versions provide csp_meta_tag helper.
  # Provide a safe no-op fallback so templates that include it won't break
  # when running on Rails versions that don't define it.
  def csp_meta_tag
    ''
  end

  # Fallback rupee formatter available to views.
  # If MoneyHelper is present this will be redundant, but guarantees availability.
  def format_rupees(amount, cents: false)
    return '' if amount.nil?
    value = cents ? (amount.to_f / 100.0) : amount.to_f
    "\u20B9#{'%.2f' % value}"
  end

  def ist_stamp(time, with_year: true)
    return '—' if time.blank?
    time.in_time_zone('Asia/Kolkata').strftime(with_year ? '%d %b %Y, %H:%M' : '%d %b, %H:%M')
  end
end
