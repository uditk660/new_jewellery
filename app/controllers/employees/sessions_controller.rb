module Employees
  class SessionsController < Devise::SessionsController
    layout 'staff_auth'

    before_action :set_devise_mapping

    private

    def set_devise_mapping
      request.env['devise.mapping'] ||= Devise.mappings[:employee]
    end
  end
end
