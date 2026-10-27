class EstimatesController < ApplicationController
  PER_PAGE = 20

  def index
    @q = params[:q].to_s.strip
    scope = Estimate.includes(:customer).order(estimate_date: :desc, estimate_no: :desc)
    if @q.present?
      like = "%#{@q.downcase}%"
      scope = scope.where(
        'LOWER(estimates.party_name) LIKE :q OR LOWER(COALESCE(estimates.party_place, \'\')) LIKE :q OR estimates.party_phone LIKE :q OR CAST(estimates.estimate_no AS CHAR) = :n',
        q: like, n: @q.delete('#')
      )
    end
    @total_count = scope.count
    @per_page = PER_PAGE
    @page = params[:page].to_i.clamp(1, helpers.index_page_count(@total_count, @per_page))
    @start_index = (@page - 1) * @per_page
    @estimates = scope.offset(@start_index).limit(@per_page)
    @open_count = Estimate.where.not(closing_fine_mg: 0).or(Estimate.where.not(closing_amount_cents: 0)).count
  end

  def show
    @estimate = Estimate.includes(:customer).find(params[:id])
    @shop = current_user.try(:shop_profile)
    @shop ||= ShopProfile.first if defined?(ShopProfile)
    render layout: false
  end

  def new
    @estimate = Estimate.new(estimate_date: Time.zone.today)
    if (customer = Customer.find_by(id: params[:customer_id]))
      apply_customer(customer)
    end
    load_form
  end

  def create
    @estimate = Estimate.new(estimate_params)
    @estimate.assign_rows(raw_rows(:items), raw_rows(:settlements))
    fill_from_customer
    saved = false
    2.times do
      saved = @estimate.save
      break
    rescue ActiveRecord::RecordNotUnique
      @estimate.estimate_no = Estimate.next_number
    end
    if saved
      redirect_to estimate_path(@estimate), notice: "Estimate #{@estimate.estimate_no} is ready to print."
    else
      load_form
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @estimate = Estimate.find(params[:id])
    load_form
  end

  def update
    @estimate = Estimate.find(params[:id])
    @estimate.assign_attributes(estimate_params)
    @estimate.assign_rows(raw_rows(:items), raw_rows(:settlements))
    fill_from_customer
    if @estimate.save
      redirect_to estimate_path(@estimate), notice: "Estimate #{@estimate.estimate_no} updated."
    else
      load_form
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    estimate = Estimate.find(params[:id])
    estimate.destroy
    redirect_to estimates_path, notice: "Estimate #{estimate.estimate_no} removed."
  end

  private

  def estimate_params
    permitted = params.require(:estimate).permit(:estimate_date, :customer_id, :party_name, :party_place, :party_phone,
                                                 :prev_ref, :prev_fine, :prev_amount, :note)
    attrs = permitted.except(:prev_fine, :prev_amount).to_h
    attrs['customer_id'] = attrs['customer_id'].presence
    attrs['prev_fine_mg'] = Estimate.mg_from(permitted[:prev_fine]) if permitted.key?(:prev_fine)
    attrs['prev_amount_cents'] = Paise.from_rupees(permitted[:prev_amount]) if permitted.key?(:prev_amount)
    attrs
  end

  def raw_rows(key)
    raw = params[key]
    rows = if raw.respond_to?(:to_unsafe_h)
             raw.to_unsafe_h.sort_by { |k, _| k.to_i }.map(&:last)
           elsif raw.is_a?(Array)
             raw
           else
             []
           end
    fields = key == :items ? %i[description jewelry_item_id pcs net_weight tunch labour labour_on] : %i[kind description weight touch fine rate amount]
    rows.map { |row| (row.respond_to?(:permit) ? row.permit(*fields).to_h : row.to_h.slice(*fields.map(&:to_s))) }
  end

  def fill_from_customer
    customer = @estimate.customer
    return unless customer

    @estimate.party_name = customer.full_name if @estimate.party_name.blank?
    @estimate.party_phone = customer.phone if @estimate.party_phone.blank?
  end

  def apply_customer(customer)
    @estimate.customer = customer
    @estimate.party_name = customer.full_name
    @estimate.party_phone = customer.phone
    @estimate.party_place = customer.address.to_s.split(/[\n,]/).map(&:strip).reject(&:blank?).last
    if (carry = Estimate.carry_forward_for(customer.id))
      @estimate.prev_ref = carry[:ref]
      @estimate.prev_fine_mg = Estimate.mg_from(carry[:fine])
      @estimate.prev_amount_cents = Paise.from_rupees(carry[:amount])
    end
  end

  def load_form
    @customers = Customer.order(:first_name, :last_name).limit(500)
    @catalogue = JewelryItem.includes(:purity, :metal).order(:name).limit(800).map do |item|
      {
        id: item.id,
        name: item.name,
        sku: item.sku.to_s,
        weight: item.weight_grams.to_f,
        tunch: item.purity&.purity_percent.to_f,
        metal: item.metal&.name.to_s
      }
    end
    @carry = {}
    Estimate.where.not(customer_id: nil).where.not(id: @estimate.id)
            .order(estimate_date: :desc, estimate_no: :desc)
            .select(:customer_id, :estimate_no, :estimate_date, :closing_fine_mg, :closing_amount_cents)
            .each do |e|
      @carry[e.customer_id] ||= {
        ref: "#{e.estimate_no}-#{e.estimate_date.strftime('%d/%m/%y')}",
        fine: Estimate.mg_to_g(e.closing_fine_mg),
        amount: Paise.rupees(e.closing_amount_cents)
      }
    end
    @gold_bhav = gold_bhav_per_10g
  end

  # Today's 24K board rate, quoted per 10 g, to prefill a bhav line.
  def gold_bhav_per_10g
    purity = Purity.joins(:metal).where('LOWER(metals.name) LIKE ?', '%gold%').order(purity_percent: :desc).first
    per_gram = purity&.updated_price.to_f
    per_gram.positive? ? (per_gram * 10 * 100 / [purity.purity_percent.to_f, 1].max).round : nil
  rescue StandardError
    nil
  end
end
