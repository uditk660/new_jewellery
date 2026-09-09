class PagesController < ApplicationController
  layout 'marketing'

  def about
  end

  def collections
    @pieces = JewelryItem.available_for_sale.includes(:metal, :purity, :jewellery_category).order(created_at: :desc).limit(8)
  end

  def contact
    @inquiry = ContactInquiry.new
  end

  def create_contact
    if params[:company_website].present?
      redirect_to contact_path, notice: 'Your note has reached the house. We will write back shortly.'
      return
    end

    @inquiry = ContactInquiry.new(inquiry_params)
    if @inquiry.save
      redirect_to contact_path, notice: 'Your note has reached the house. We will write back shortly.'
    else
      render :contact
    end
  end

  private

  def inquiry_params
    params.require(:contact_inquiry).permit(:name, :email, :phone, :subject, :message)
  end
end
