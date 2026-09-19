class ReportsController < ApplicationController
  def index
    @report = HouseReport.for(params, returns: session[:return_records], house_name: house_name)
    @house_name = house_name
    @metals = Metal.ordered
  end

  def new
    @metals = Metal.ordered
    @window = ProfitLoss::WINDOWS.include?(params[:window].to_s) ? params[:window].to_s : 'month'
    @from, @to = ProfitLoss.range_for(@window, params)
    @metal_id = params[:metal_id].presence
  end

  def sales_log
    @house_name = house_name
    @metals = Metal.ordered
    @window = ProfitLoss::WINDOWS.include?(params[:window].to_s) ? params[:window].to_s : 'today'
    @log = ProfitLoss.for(
      { window: @window, from: params[:from], to: params[:to], metal_id: params[:metal_id] },
      returns: []
    )
    @snapshots = sales_log_snapshots(@log.metal_id)
    @pieces = sales_log_pieces(@log)
    @entries = @log.bills
    @truncated = false
    if (@log.to - @log.from).to_i > 90 && @entries.size > 80
      @entries = @entries.first(80)
      @truncated = true
    end
    @series = @log.series(:total)
    @series_max = @log.series_max(:total)
  end

  private

  def sales_log_snapshots(metal_id)
    today = Time.zone.today
    year = ProfitLoss.for({ window: 'year', metal_id: metal_id }, returns: [])
    {
      'today' => [today, today, 'Today'],
      'yesterday' => [today - 1, today - 1, 'Yesterday'],
      'week' => [today.beginning_of_week, today.end_of_week, 'This week'],
      'month' => [today.beginning_of_month, today.end_of_month, today.strftime('%B')],
      'year' => [today.beginning_of_year, today.end_of_year, today.strftime('%Y')]
    }.map do |key, (from, to, label)|
      slices = year.slices.select { |row| row[:date] >= from && row[:date] <= to }
      {
        key: key,
        label: label,
        bills: slices.size,
        pieces: slices.sum { |row| row[:pcs] },
        grams: slices.sum { |row| row[:grams] },
        total: slices.sum { |row| row[:total] }
      }
    end
  end

  def sales_log_pieces(book)
    groups = {}
    book.orders.each do |order|
      order.line_items.each do |item|
        jewelry = item.jewelry_item
        next if book.metal_id.present? && jewelry&.metal_id.to_s != book.metal_id.to_s

        key = jewelry&.id || 0
        groups[key] ||= {
          item: jewelry,
          name: jewelry&.name.presence || 'Piece',
          sku: jewelry&.sku,
          metal: jewelry&.metal&.name,
          purity: jewelry&.purity&.name,
          pcs: 0,
          grams: 0.0,
          amount: 0.0
        }
        groups[key][:pcs] += item.quantity.to_i
        groups[key][:grams] += item.net_weight.to_f * item.quantity.to_i
        groups[key][:amount] += item.line_amount.to_f
      end
    end
    groups.values.sort_by { |row| -row[:amount] }.first(8)
  end

  def house_name
    current_user.try(:shop_profile).try(:shop_name).presence ||
      current_user.try(:shop_name).presence ||
      current_user.try(:display_name).presence ||
      'The house'
  end
end
