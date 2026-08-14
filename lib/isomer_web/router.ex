defmodule IsomerWeb.Router do
  use IsomerWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {IsomerWeb.Layouts, :root})
    # Custom wrapper: auth POST CSRF races redirect instead of bare "Forbidden".
    plug(IsomerWeb.Plugs.ForgeryProtection)
    plug(:put_secure_browser_headers)
    plug(IsomerWeb.UserAuth)
  end

  # Liveness only — no browser pipeline (no CSRF/session/auth).
  scope "/", IsomerWeb do
    get("/health", HealthController, :show)
  end

  scope "/", IsomerWeb do
    pipe_through(:browser)

    get("/", PageController, :home)

    get("/login", SessionController, :new)
    post("/session", SessionController, :create)
    post("/session/signup", SessionController, :signup)
    delete("/session", SessionController, :delete)
    get("/logout", SessionController, :delete)

    get("/artifacts/:id/download", ArtifactController, :download)
    post("/settings", SettingsController, :update)

    live_session :authenticated,
      on_mount: [{IsomerWeb.UserAuth, :ensure_authenticated}] do
      live("/orgs", OrgLive.Index, :index)
      live("/orgs/new", OrgLive.New, :new)
      live("/orgs/:org_id", OrgLive.Show, :show)
      live("/orgs/:org_id/members", OrgLive.Members, :index)
      live("/orgs/:org_id/assessments/new", AssessmentLive.New, :new)
      live("/assessments/:id", AssessmentLive.Show, :show)
      live("/assessments/:id/q", AssessmentLive.Wizard, :wizard)
      live("/assessments/:id/results", AssessmentLive.Results, :results)
      live("/assessments/:id/artifacts", AssessmentLive.Artifacts, :index)
      live("/library", LibraryLive, :index)
      live("/settings", SettingsLive, :index)
    end
  end
end
