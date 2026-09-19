# Strucxil licence-desk earnings from granted years.
# A year counts when it has a start date and was not left pending or declined.
class LicenceEarnings
  attr_reader :month

  def initialize(month: nil)
    @month = parse_month(month)
  end

  def today_cents
    sum_for(zone.now.beginning_of_day..zone.now.end_of_day)
  end

  def month_cents
    sum_for(month_range)
  end

  def year_cents
    sum_for(year_range)
  end

  def all_time_cents
    earned_scope.sum('plans.price_cents').to_i
  end

  def live_cents
    live_scope.sum('plans.price_cents').to_i
  end

  def today_count
    count_for(zone.now.beginning_of_day..zone.now.end_of_day)
  end

  def month_count
    count_for(month_range)
  end

  def year_count
    count_for(year_range)
  end

  def live_count
    live_scope.count
  end

  def month_label
    month.strftime('%B %Y')
  end

  def prev_month
    month.prev_month.beginning_of_month
  end

  def next_month
    month.next_month.beginning_of_month
  end

  def showing_current_month?
    month == zone.today.beginning_of_month
  end

  def day_rows
    grouped = Hash.new { |h, k| h[k] = { cents: 0, count: 0 } }
    month_grants.each do |sub|
      day = sub.starts_at.in_time_zone(zone).to_date
      grouped[day][:cents] += sub.plan.price_cents.to_i
      grouped[day][:count] += 1
    end

    (month.beginning_of_month..month.end_of_month).map do |day|
      row = grouped[day]
      { date: day, cents: row[:cents], count: row[:count], today: day == zone.today }
    end
  end

  def calendar_blanks
    month.beginning_of_month.wday.then { |w| w.zero? ? 6 : w - 1 }
  end

  def active_days
    day_rows.select { |row| row[:cents].positive? }
  end

  def month_peak_cents
    day_rows.map { |row| row[:cents] }.max.to_i
  end

  def year_months
    grouped = Hash.new { |h, k| h[k] = { cents: 0, count: 0 } }
    year_grants.each do |sub|
      key = sub.starts_at.in_time_zone(zone).beginning_of_month.to_date
      grouped[key][:cents] += sub.plan.price_cents.to_i
      grouped[key][:count] += 1
    end

    cursor = month.beginning_of_year
    12.times.map do
      row = grouped[cursor]
      item = { date: cursor, cents: row[:cents], count: row[:count], current: cursor == month }
      cursor = cursor.next_month
      item
    end
  end

  def by_plan
    counts = Hash.new { |h, k| h[k] = { cents: 0, count: 0, name: k } }
    month_grants.each do |sub|
      key = sub.plan.name
      counts[key][:cents] += sub.plan.price_cents.to_i
      counts[key][:count] += 1
    end
    counts.values.sort_by { |row| -row[:cents] }
  end

  def recent_grants
    earned_scope.includes(:user, :plan).order(starts_at: :desc).limit(12)
  end

  def month_grants
    @month_grants ||= earned_scope.includes(:user, :plan).where(starts_at: month_range).order(starts_at: :desc).to_a
  end

  private

  def zone
    Time.zone
  end

  def parse_month(value)
    return zone.today.beginning_of_month if value.blank?
    text = value.to_s
    parsed = text.match?(/\A\d{4}-\d{2}\z/) ? Date.parse("#{text}-01") : Date.parse(text)
    parsed.beginning_of_month
  rescue ArgumentError, TypeError
    zone.today.beginning_of_month
  end

  def month_range
    month.beginning_of_month.beginning_of_day..month.end_of_month.end_of_day
  end

  def year_range
    month.beginning_of_year.beginning_of_day..month.end_of_year.end_of_day
  end

  def earned_scope
    Subscription.joins(:plan)
                .where.not(starts_at: nil)
                .where.not(status: %w[pending rejected])
  end

  def live_scope
    Subscription.joins(:plan)
                .where(status: 'active')
                .where('ends_at >= ?', Time.current)
  end

  def sum_for(range)
    earned_scope.where(starts_at: range).sum('plans.price_cents').to_i
  end

  def count_for(range)
    earned_scope.where(starts_at: range).count
  end

  def year_grants
    @year_grants ||= earned_scope.includes(:plan).where(starts_at: year_range).to_a
  end
end
