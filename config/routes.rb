Rails.application.routes.draw do
  begin
    require 'devise'
  rescue LoadError
  end

  devise_for :employees, path: 'employee', skip: [:registrations], controllers: { sessions: 'employees/sessions' }
  devise_for :users, controllers: { registrations: 'users/registrations' }

  namespace :staff, path: 'employee' do
    root to: 'dashboard#show'
    resources :subscription_requests, only: [:index, :show] do
      member do
        post :approve
        post :reject
      end
    end
    resources :subscriptions, only: [:index, :new, :create, :show] do
      member do
        post :cancel
        post :suspend
        post :reactivate
      end
    end
    resources :plans, only: [:index, :new, :create]
    resources :logs, only: [:index]
    resource :earnings, only: [:show], controller: 'earnings'
  end

  resource :subscription, only: [:new, :create] do
    get :pending, on: :collection
  end
  resource :shop_setup, only: [:show, :update]
  resource :shop_profile, only: [:show]

  root to: 'home#dashboard'
  get 'about', to: 'pages#about', as: :about
  get 'collections', to: 'pages#collections', as: :collections
  get 'contact', to: 'pages#contact', as: :contact
  post 'contact', to: 'pages#create_contact'

  get 'i/:token', to: 'orders#shared_invoice', as: :shared_invoice, constraints: { token: /[A-Za-z0-9\-_]{16,64}/ }
  get 'r/:token', to: 'payments#shared_invoice', as: :shared_receipt, constraints: { token: /[A-Za-z0-9\-_]{16,64}/ }

  resources :jewelry_items do
    member do
      post :archive
      post :unarchive
    end
  end
  resources :orders, only: [:index, :show, :new, :create] do
    member do
      post :record_payment
      get :invoice
    end
  end

  get 'pos', to: 'pos#index', as: :pos
  post 'pos/charge', to: 'pos#charge', as: :pos_charge
  post 'pos/create_order', to: 'pos#create_order', as: :pos_create_order

  resources :rates, only: [:index, :new, :create, :edit, :update]
  resources :inventory_items, only: [:index, :show, :new, :create]
  resources :stock_movements, only: [:create]
  resources :ledgers, only: [:index, :show, :new, :create]
  resources :profit_losses, only: [:index, :new]
  resources :reports, only: [:index, :new]
  get 'reports/sales_log', to: 'reports#sales_log', as: :sales_log_reports
  get 'security', to: 'security#index', as: :security_index
  get 'security/new', to: 'security#new', as: :new_security
  resources :metals, only: [:index, :new, :create, :show, :update, :destroy]
  resources :purities, only: [:index, :new, :create, :show, :edit, :update]
  resources :customers
  resources :payments, only: [:show] do
    member do
      get :invoice
    end
  end
  resources :jewellery_categories, only: [:index, :new, :create]
  resources :stores, only: [:index, :new, :create, :show, :edit, :update]
  resources :metal_stocks, only: [:index, :new, :create, :show, :update] do
    member do
      get :adjust
      post :do_adjust
    end
  end
  resources :returns, only: [:index, :new, :create, :show]
end
