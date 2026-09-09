class HomeController < ApplicationController
  def dashboard
    unless user_signed_in?
      render 'pages/home', layout: 'marketing'
      return
    end

  scope = Order.where(status: 'paid')
    today = Time.zone.today
  # compute totals using line_item.line_amount to reflect per-gram * net_weight * qty + making
  @today_total = scope.where(sale_date: today).sum { |o| o.line_items.sum(&:line_amount) }
    week_start = today.beginning_of_week
    week_end = today.end_of_week
  @week_total = scope.where(sale_date: week_start..week_end).sum { |o| o.line_items.sum(&:line_amount) }
  @month_total = scope.where(sale_date: today.beginning_of_month..today.end_of_month).sum { |o| o.line_items.sum(&:line_amount) }

  @recent_orders = Order.where(status: 'paid').order(sale_date: :desc).limit(6)

  # low stock jewelry items (quantity <= 5)
  @low_stock_items = JewelryItem.where('quantity <= ?', 5).order(:quantity).limit(8)

    # top items this week
  @top_items_week = LineItem.joins(:order, :jewelry_item)
               .where(orders: { status: 'paid', sale_date: week_start..week_end })
               .group('jewelry_items.id', 'jewelry_items.name')
                             .select('jewelry_items.id, jewelry_items.name, SUM(line_items.quantity) as qty_sold, SUM(line_items.price_cents * line_items.quantity)/100.0 as sales_amount')
                             .order('SUM(line_items.quantity) DESC')
                             .limit(8)
    
    # daily sales for last 7 days (for small chart)
    range_start = (today - 6)
    dates = (range_start..today).to_a
    @sales_labels = dates.map { |d| d.strftime('%a') }
  @sales_values = dates.map { |d| scope.where(sale_date: d).sum { |o| o.line_items.sum(&:line_amount) } }
    @sales_max = @sales_values.max || 0
  # Today's rates per metal (most recent rate for today)
  @today_rates = Rate.where(date: today).order(metal_type: :asc)
  end
end
