defmodule ChatAppWeb.Presence do
  @moduledoc """
  Provides Presence tracking for connected users.
  """
  use Phoenix.Presence,
    otp_app: :chat_app,
    pubsub_server: ChatApp.PubSub
end
