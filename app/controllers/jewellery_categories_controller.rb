class JewelleryCategoriesController < ApplicationController
  def index
    redirect_to metals_path
  end

  def new
    redirect_to new_metal_path
  end

  def create
    redirect_to metals_path, alert: 'Add categories on the metal itself.'
  end
end
