defmodule ChatAppWeb.RoomLive do
  use ChatAppWeb, :live_view

  @topic "room:lobby"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ChatApp.PubSub, @topic)
      {:ok, _} = ChatAppWeb.Presence.track(self(), @topic, inspect(self()), %{user: "User", online_at: inspect(System.system_time(:second))})
    end

    history = ChatApp.ChatRoom.get_history()
    online_users = if connected?(socket), do: ChatAppWeb.Presence.list(@topic), else: %{}

    socket =
      socket
      |> stream(:messages, history)
      |> assign(:online_users, online_users)
      |> assign(:typing_users, %{})
      |> assign(:form, to_form(%{"user" => "User", "text" => ""}))

    {:ok, socket}
  end

  @impl true
  def handle_event("send", %{"user" => user, "text" => text}, socket) do
    user = if String.trim(user) == "", do: "Anonymous", else: String.trim(user)

    case ChatApp.ChatRoom.send_message(user, text) do
      {:ok, _message} ->
        Phoenix.PubSub.broadcast(ChatApp.PubSub, @topic, {:stop_typing, user})
        {:noreply, assign(socket, :form, to_form(%{"user" => user, "text" => ""}))}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_user", %{"user" => user}, socket) do
    user = if String.trim(user) == "", do: "User", else: String.trim(user)

    if connected?(socket) do
      ChatAppWeb.Presence.update(self(), @topic, inspect(self()), %{user: user, online_at: inspect(System.system_time(:second))})
    end

    current_text = socket.assigns.form[:text].value || ""
    {:noreply, assign(socket, :form, to_form(%{"user" => user, "text" => current_text}))}
  end

  @impl true
  def handle_event("typing", _params, socket) do
    username = socket.assigns.form[:user].value || "Someone"
    Phoenix.PubSub.broadcast(ChatApp.PubSub, @topic, {:user_typing, username})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    {:noreply, stream_insert(socket, :messages, message)}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :online_users, ChatAppWeb.Presence.list(@topic))}
  end

  @impl true
  def handle_info({:user_typing, username}, socket) do
    if old_ref = Map.get(socket.assigns.typing_users, username) do
      Process.cancel_timer(old_ref)
    end

    timer_ref = Process.send_after(self(), {:stop_typing, username}, 2000)
    updated_typing = Map.put(socket.assigns.typing_users, username, timer_ref)

    {:noreply, assign(socket, :typing_users, updated_typing)}
  end

  @impl true
  def handle_info({:stop_typing, username}, socket) do
    if old_ref = Map.get(socket.assigns.typing_users, username) do
      Process.cancel_timer(old_ref)
    end

    updated_typing = Map.delete(socket.assigns.typing_users, username)
    {:noreply, assign(socket, :typing_users, updated_typing)}
  end

  defp format_typing_users(typing_map, current_user) do
    users = Map.keys(typing_map) |> Enum.reject(&(&1 == current_user))

    case users do
      [single] -> "#{single} is typing..."
      [u1, u2] -> "#{u1} and #{u2} are typing..."
      [u1, u2 | rest] -> "#{u1}, #{u2} and #{length(rest)} others are typing..."
      _ -> ""
    end
  end

  @impl true
  def render(assigns) do
    current_user = assigns.form[:user].value || "User"
    typing_text = format_typing_users(assigns.typing_users, current_user)
    assigns = assign(assigns, :typing_text, typing_text)

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto my-3 p-4 sm:p-6 bg-slate-900/95 text-slate-100 backdrop-blur-md rounded-2xl shadow-2xl border border-slate-800 flex flex-col h-[calc(100vh-5rem)] sm:h-[82vh] min-h-[500px]">
        <!-- Header -->
        <div class="flex items-center justify-between pb-4 mb-4 border-b border-slate-800/80 flex-none">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-indigo-500 to-violet-500 flex items-center justify-center text-white font-bold text-lg shadow-lg shadow-indigo-500/30">
              <.icon name="hero-chat-bubble-left-right" class="w-6 h-6" />
            </div>
            <div>
              <h1 class="text-xl font-bold bg-gradient-to-r from-white via-slate-200 to-indigo-300 bg-clip-text text-transparent">
                Lobby Chat
              </h1>
              <p class="text-xs text-slate-400 flex items-center gap-1.5 mt-0.5">
                <span class="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
                Live in-memory stream
              </p>
            </div>
          </div>

          <!-- Presence Pill -->
          <div class="flex items-center gap-2 px-3 py-1.5 bg-slate-800/80 border border-slate-700/60 rounded-full text-xs text-slate-300 shadow-inner">
            <.icon name="hero-user-group" class="w-4 h-4 text-emerald-400" />
            <span class="font-semibold text-white">{map_size(@online_users)}</span>
            <span class="text-slate-400">online</span>
          </div>
        </div>

        <!-- Messages Stream Container -->
        <div
          id="messages"
          phx-update="stream"
          class="flex-1 overflow-y-auto space-y-3 pr-2 min-h-0 scrollbar-thin scrollbar-thumb-slate-700 scrollbar-track-transparent"
        >
          <div
            :for={{dom_id, message} <- @streams.messages}
            id={dom_id}
            class="flex flex-col space-y-1 bg-slate-800/60 p-3.5 rounded-xl border border-slate-700/50 hover:border-slate-600/50 transition-all"
          >
            <div class="flex items-center justify-between text-xs text-slate-400">
              <span class="font-semibold text-indigo-400 flex items-center gap-1.5">
                <span class="w-6 h-6 rounded-full bg-indigo-950 border border-indigo-700/50 flex items-center justify-center text-[10px] text-indigo-300 font-bold uppercase">
                  {String.first(message.user || "A")}
                </span>
                {message.user}
              </span>
              <span class="text-[11px] opacity-75">
                {Calendar.strftime(message.inserted_at, "%H:%M:%S")}
              </span>
            </div>
            <p class="text-slate-200 text-sm leading-relaxed pl-7 break-words">
              {message.text}
            </p>
          </div>
        </div>

        <!-- Typing Indicator Bar -->
        <div class="h-6 mt-2 flex items-center flex-none">
          <div :if={@typing_text != ""} class="flex items-center text-xs text-indigo-400 font-medium animate-pulse gap-1.5 px-1">
            <.icon name="hero-pencil-solid" class="w-3.5 h-3.5" />
            <span>{@typing_text}</span>
          </div>
        </div>

        <!-- Message Input Form -->
        <form
          phx-submit="send"
          class="pt-2 border-t border-slate-800/80 flex flex-col sm:flex-row gap-3 items-center flex-none"
        >
          <div class="w-full sm:w-44 flex-none">
            <input
              type="text"
              name="user"
              value={@form[:user].value}
              phx-change="update_user"
              placeholder="Username"
              required
              class="w-full px-3.5 py-2 bg-slate-800/90 border border-slate-700/80 rounded-xl text-slate-100 placeholder-slate-500 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all"
            />
          </div>

          <div class="flex-1 w-full flex gap-2.5 items-center">
            <input
              type="text"
              name="text"
              value={@form[:text].value}
              phx-keydown="typing"
              phx-throttle="2000"
              placeholder="Type your message..."
              autocomplete="off"
              required
              class="flex-1 px-4 py-2 bg-slate-800/90 border border-slate-700/80 rounded-xl text-slate-100 placeholder-slate-500 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all"
            />
            <button
              type="submit"
              class="px-5 py-2 bg-indigo-600 hover:bg-indigo-500 active:bg-indigo-700 text-white font-medium rounded-xl text-sm transition-all shadow-lg shadow-indigo-600/30 flex items-center justify-center gap-2 cursor-pointer flex-none h-[38px]"
            >
              <span>Send</span>
              <.icon name="hero-paper-airplane" class="w-4 h-4" />
            </button>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
