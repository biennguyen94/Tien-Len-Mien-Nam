defmodule TienLenWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TienLenWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  attr :wide, :boolean, default: false, doc: "use the full width (game table)"
  attr :current_user, :any, default: nil, doc: "the logged-in user, if any"
  attr :announcement, :string, default: nil, doc: "lobby announcement (AD9)"
  attr :social, :map, default: nil, doc: "private chat panel and invite popup (G7, G8)"

  attr :action_bar, :boolean,
    default: false,
    doc: "the page has a sticky bar at the bottom on phones (table): lift the 💬 button"

  def app(assigns) do
    ~H"""
    <%!-- M3: on phones (< 640px, Tailwind `sm`) the nav collapses behind a ☰ button; from
         `sm` up it is the single row it always was. The coin badge stays visible on phones. --%>
    <header class="border-b border-base-300">
      <div class="flex flex-wrap items-center gap-x-2 gap-y-1 px-3 py-2 sm:px-6 lg:px-8 min-h-16">
        <.link navigate={~p"/"} class="flex-1 min-w-0 truncate text-lg font-bold tracking-tight">
          ♠ Tiến Lên Miền Nam
        </.link>
        <.link
          :if={@current_user}
          navigate={~p"/lich-su-coin"}
          id="my-coins-mobile"
          class="badge badge-warning tabular-nums sm:hidden"
          title="Lịch sử coin"
        >
          🪙 {TienLenWeb.Text.coins(@current_user.coins)}
        </.link>
        <button
          :if={@current_user}
          id="nav-menu-toggle"
          type="button"
          class="btn btn-ghost btn-sm btn-square relative sm:hidden"
          aria-label="Menu"
          aria-controls="site-nav"
          aria-expanded="false"
          phx-click={
            JS.toggle_class("hidden flex", to: "#site-nav")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
        >
          <.icon name="hero-bars-3" class="size-6" />
          <span
            :if={@social && @social.requests > 0}
            class="absolute top-0 right-0 size-2.5 rounded-full bg-error"
          />
        </button>
        <nav
          id="site-nav"
          class={[
            "w-full sm:w-auto flex-col items-stretch sm:flex-row sm:flex sm:flex-wrap sm:items-center gap-1 sm:gap-2 py-1 sm:py-0",
            if(@current_user, do: "hidden", else: "flex")
          ]}
        >
          <.link
            :if={@current_user && @current_user.role == "admin"}
            navigate={~p"/quan-tri"}
            id="admin-link"
            class="btn btn-ghost btn-sm justify-start sm:justify-center text-error"
          >
            Quản trị
          </.link>
          <.link
            :if={@current_user}
            navigate={~p"/bang-xep-hang"}
            class="btn btn-ghost btn-sm justify-start sm:justify-center"
          >
            Bảng xếp hạng
          </.link>
          <.link
            :if={@current_user}
            navigate={~p"/lich-su"}
            class="btn btn-ghost btn-sm justify-start sm:justify-center"
          >
            Lịch sử
          </.link>
          <.link
            :if={@current_user}
            navigate={~p"/cua-hang"}
            id="shop-link"
            class="btn btn-ghost btn-sm justify-start sm:justify-center"
          >
            Cửa hàng
          </.link>
          <.link
            :if={@current_user}
            navigate={~p"/ban-be"}
            id="friends-link"
            class="btn btn-ghost btn-sm justify-start sm:justify-center"
          >
            Bạn bè
            <span
              :if={@social && @social.requests > 0}
              id="friend-requests"
              class="badge badge-error badge-sm"
            >
              {@social.requests}
            </span>
          </.link>
          <.link
            :if={@current_user}
            navigate={~p"/lich-su-coin"}
            id="my-coins"
            class="badge badge-warning badge-lg tabular-nums hidden sm:inline-flex"
            title="Lịch sử coin"
          >
            🪙 {TienLenWeb.Text.coins(@current_user.coins)}
          </.link>
          <.link
            :if={@current_user}
            navigate={~p"/nguoi-choi/#{@current_user.username}"}
            id="current-user"
            class="text-sm link link-hover px-3 py-1 sm:p-0 truncate"
            title="Hồ sơ của bạn"
          >
            {TienLenWeb.Text.avatar(@current_user)} {@current_user.display_name}
            <span class="text-base-content/60">(@{@current_user.username})</span>
          </.link>
          <.link
            :if={@current_user}
            id="logout"
            href={~p"/dang-xuat"}
            method="delete"
            class="btn btn-ghost btn-sm justify-start sm:justify-center"
          >
            Đăng xuất
          </.link>
          <div class="px-3 py-1 sm:p-0 w-fit"><.theme_toggle /></div>
        </nav>
      </div>
    </header>

    <div :if={@announcement} id="announcement" class="alert alert-info rounded-none justify-center">
      📢 {@announcement}
    </div>

    <%!-- M3: bottom padding on phones so the 💬 button never covers the last inputs --%>
    <main class="px-3 pt-6 pb-24 sm:px-6 sm:pb-6 lg:px-8">
      <div class={["mx-auto space-y-4", if(@wide, do: "max-w-5xl", else: "max-w-2xl")]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <TienLenWeb.Social.panel :if={@social} social={@social} raised={@action_bar} />
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
