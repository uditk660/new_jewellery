module Staff
  class PlansController < BaseController
    def index
      @plans = Plan.order(:position, :price_cents)
    end

    def new
      @plan = Plan.new
    end

    def create
      @plan = Plan.new(plan_params)
      if @plan.save
        log_action!('created_plan', plan: @plan)
        redirect_to staff_plans_path, notice: "Plan “#{@plan.name}” added."
      else
        render :new
      end
    end

    private

    def plan_params
      permitted = params.require(:plan).permit(:name, :tagline, :description, :features, :active, :featured, :position)
      rupees = params[:price_rupees]
      permitted[:price_cents] = (rupees.to_f * 100).round if rupees.present?
      permitted
    end
  end
end
