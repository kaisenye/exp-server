Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application layout)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"

  # API routes
  namespace :api do
    namespace :v1 do
      get "health", to: "health#index"

      # Authentication routes
      namespace :auth do
        post "login", to: "sessions#create"
        delete "logout", to: "sessions#destroy"
        post "register", to: "registrations#create"
        get "me", to: "users#show"
      end

      # Accounts API
      resources :accounts do
        member do
          post :sync
        end
      end

      # Transactions API
      resources :transactions, only: [ :index, :show ] do
        collection do
          post :sync
          get :uncategorized
          get "by_category/:category_id", to: "transactions#by_category", as: :by_category
        end
        member do
          put :categorize
        end
      end

      # Categories API
      resources :categories do
        collection do
          get :budget_overview
          get :spending_analysis
        end
      end

      # Add more API endpoints here
    end
  end
end
