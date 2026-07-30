defmodule ChatApp.ChatRoom do
  @moduledoc """
  In-memory chat room process managing message history and broadcasting events.
  """
  use GenServer

  @pubsub ChatApp.PubSub
  @topic "room:lobby"
  @max_history 50

  # Client API

  @doc """
  Starts the ChatRoom GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sends a message, updates state, and broadcasts it to the PubSub topic.
  """
  def send_message(user, text) when is_binary(user) and is_binary(text) do
    user = String.trim(user)
    text = String.trim(text)

    if byte_size(text) > 0 do
      user = if byte_size(user) == 0, do: "Anonymous", else: user
      GenServer.call(__MODULE__, {:send_message, user, text})
    else
      {:error, :empty_message}
    end
  end

  @doc """
  Returns the last 50 messages in chronological order.
  """
  def get_history do
    GenServer.call(__MODULE__, :get_history)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, []}
  end

  @impl true
  def handle_call({:send_message, user, text}, _from, messages) do
    message = %{
      id: Integer.to_string(System.unique_integer([:positive])),
      user: user,
      text: text,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    Phoenix.PubSub.broadcast(@pubsub, @topic, {:new_message, message})

    # Store new messages at the head of the list, keeping up to 50
    new_messages = [message | messages] |> Enum.take(@max_history)

    {:reply, {:ok, message}, new_messages}
  end

  @impl true
  def handle_call(:get_history, _from, messages) do
    # Return messages in chronological order (oldest to newest)
    chronological_messages = Enum.reverse(messages)
    {:reply, chronological_messages, messages}
  end
end
