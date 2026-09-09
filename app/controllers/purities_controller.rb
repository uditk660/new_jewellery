class PuritiesController < ApplicationController
  before_action :set_purity, only: [:show, :edit, :update]

  def index
    redirect_to metals_path
  end

  def new
    redirect_to new_metal_path
  end

  def show
    redirect_to metal_path(@purity.metal)
  end

  def edit
    @metals = Metal.ordered
  end

  def update
    if @purity.update(purity_params)
      redirect_to metal_path(@purity.metal), notice: 'Hallmark updated.'
    else
      @metals = Metal.ordered
      render :edit
    end
  end

  def create
    redirect_to metals_path, alert: 'Add hallmarks on the metal itself.'
  end

  private

  def set_purity
    @purity = Purity.find_by(id: params[:id])
    redirect_to(metals_path, alert: 'Hallmark not found.') and return unless @purity
  end

  def purity_params
    params.require(:purity).permit(
      :metal_id, :name, :purity_percent, :active, :updated_price, :remarks,
      :fineness, :hallmark_standard, :wastage_percent, :making_charge_percent, :position
    )
  end
end
