defmodule IsomerWeb.Router do
  use IsomerWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {IsomerWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(IsomerWeb.UserAuth)
  end

  scope "/", IsomerWeb do
    pipe_through(:browser)

    get("/", PageController, :home)

    get("/login", SessionController, :new)
    post("/session", SessionController, :create)
    post("/session/signup", SessionController, :signup)
    delete("/session", SessionController, :delete)
    get("/logout", SessionController, :delete)

    live_session :authenticated,
      on_mount: [{IsomerWeb.UserAuth, :ensure_authenticated}] do
      live("/orgs", OrgLive.Index, :index)
      live("/orgs/new", OrgLive.New, :new)
      live("/orgs/:org_id", OrgLive.Show, :show)
      live("/orgs/:org_id/assessments/new", AssessmentLive.New, :new)
      live("/assessments/:id", AssessmentLive.Show, :show)
      live("/assessments/:id/q", AssessmentLive.Wizard, :wizard)
    end
  end
end
