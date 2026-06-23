defmodule FeedPugWeb.Router do
  use FeedPugWeb, :router

  import FeedPugWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FeedPugWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_authenticated do
    plug FeedPugWeb.Plugs.ApiAuth
  end

  # JSON API for the mobile client (Bearer token via the device-pairing flow).
  scope "/api", FeedPugWeb.Api do
    pipe_through [:api, :api_authenticated]

    get "/profile", ProfileController, :show

    get "/timeline", TimelineController, :index
    post "/timeline/read_all", TimelineController, :read_all

    get "/items/:id", ItemController, :show
    post "/items/:id/read", ItemController, :read
    post "/items/:id/unread", ItemController, :unread
    post "/items/:id/reactions", ItemController, :react

    get "/sources", SourceController, :index
    get "/slices", SourceController, :slices
    get "/reactions", SourceController, :reactions

    get "/groups", GroupController, :index
    post "/groups", GroupController, :create
    delete "/groups/:id", GroupController, :delete
    post "/groups/:id/feeds", GroupController, :add_feed
    delete "/group_feeds/:id", GroupController, :remove_feed

    get "/follows", FollowController, :index
    get "/discover", FollowController, :discover
    post "/follows", FollowController, :create
    delete "/follows/:id", FollowController, :delete
  end

  # Other scopes may use custom stacks.
  # scope "/api", FeedPugWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:feed_pug, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FeedPugWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", FeedPugWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{FeedPugWeb.UserAuth, :require_authenticated}] do
      live "/", NewsfeedLive, :index
      live "/groups", GroupsLive, :index
      live "/discover", DiscoverLive, :index
      live "/devices", DevicesLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", FeedPugWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{FeedPugWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
