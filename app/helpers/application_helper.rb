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

  # 1-based serial on paginated index tables (position is 0-based within the current page).
  def index_serial(position, offset: nil)
    base = offset.nil? ? index_page_offset : offset.to_i
    base + position.to_i + 1
  end

  def index_page_offset
    if defined?(@start_index) && @start_index
      @start_index.to_i
    elsif @page.present? && @per_page.present?
      ([@page.to_i, 1].max - 1) * @per_page.to_i
    else
      0
    end
  end

  def index_page_count(total_count, per_page)
    per = per_page.to_i
    return 1 if per <= 0

    [(total_count.to_i.to_f / per).ceil, 1].max
  end
end
