class ShopSetupsController < ApplicationController
  skip_before_action :enforce_shop_setup!
  before_action :require_live_subscription

  def show
    @profile = current_user.shop_profile || current_user.build_shop_profile(profile_defaults)
  end

  def update
    @profile = current_user.shop_profile || current_user.build_shop_profile
    @profile.assign_attributes(shop_profile_params)

    if @profile.save
      @profile.update_column(:completed_at, Time.current) if @profile.completed_at.blank?
      sync_user_from_profile!(@profile)
      redirect_to root_path, notice: 'Showroom details saved. Welcome to your catalogue.'
    else
      render :show
    end
  end

  private

  def require_live_subscription
    return if subscription_live?

    sub = current_user.current_subscription
    if sub && %w[pending suspended].include?(sub.effective_status)
      redirect_to pending_subscription_path
    else
      redirect_to new_subscription_path
    end
  end

  def profile_defaults
    {
      shop_name: current_user.shop_name,
      owner_name: current_user.full_name,
      phone: current_user.phone,
      email: current_user.email,
      country: 'India'
    }
  end

  def sync_user_from_profile!(profile)
    current_user.update(
      shop_name: profile.shop_name,
      full_name: profile.owner_name,
      phone: profile.phone
    )
  end

  def shop_profile_params
    params.require(:shop_profile).permit(
      :shop_name, :legal_name, :owner_name, :tagline,
      :phone, :alternate_phone, :whatsapp, :email, :website,
      :address_line1, :address_line2, :city, :state, :pincode, :country,
      :gstin, :pan, :registration_number, :cin,
      :bis_hallmark_licence, :hallmark_center, :hallmark_center_code,
      :jeweller_type, :association_membership, :established_year, :working_hours,
      :bank_name, :account_holder, :account_number, :ifsc,
      :invoice_declaration
    )
  end
end
