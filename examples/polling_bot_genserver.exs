# GenServer-based Telegram polling bot - examples/polling_bot_genserver.exs
#
# Wymagania:
# - Ustaw zmienną środowiskową TELEGRAM_BOT_TOKEN z tokenem bota
# - Dodaj do mix.exs zależności: {:httpoison, "~> 1.8"}, {:jason, "~> 1.2"}
#   i uruchom `mix deps.get` przed uruchomieniem skryptu
#
# Uruchomienie jako skrypt:
#   elixir examples/polling_bot_genserver.exs
#
# Lub zintegrowanie z aplikacją OTP: dodać PollingBot.Supervisor do tree nadzorczego.

defmodule PollingBot do
  @moduledoc """
  GenServer-based polling bot example. Przechowuje offset w stanie i cyklicznie
  pobiera updates z API Telegrama.

  Zachowanie:
  - Obsługuje /start (wysyła powitanie) i echo pozostałych wiadomości.
  - Automatyczny backoff przy błędach.
  """

  use GenServer
  require Logger

  @poll_interval 1_000    # ms pomiędzy pollami gdy brak błędu
  @error_backoff 5_000    # ms przy błędzie
  @get_updates_timeout 10 # seconds (parameter dla getUpdates)

  # Public API
  def start_link(opts \ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  # GenServer callbacks
  def init(_opts) do
    token = System.get_env("TELEGRAM_BOT_TOKEN") || raise "Ustaw zmienną środowiskową TELEGRAM_BOT_TOKEN"
    base = "https://api.telegram.org/bot#{token}"
    state = %{base: base, offset: 0, timer: nil}

    # Uruchom pierwszy poll natychmiast
    send(self(), :poll)
    {:ok, state}
  end

  def handle_info(:poll, %{base: base, offset: offset} = state) do
    case get_updates(base, offset) do
      {:ok, updates} when is_list(updates) ->
        new_offset = Enum.reduce(updates, offset, fn upd, acc ->
          handle_update(base, upd)
          update_id = get_in(upd, ["update_id"]) || 0
          max(acc, update_id + 1)
        end)

        # zaplanuj kolejny poll
        Process.send_after(self(), :poll, @poll_interval)
        {:noreply, %{state | offset: new_offset}}

      {:error, reason} ->
        Logger.error("Błąd pobierania updates: #{inspect(reason)}. Backoff #{@error_backoff}ms")
        Process.send_after(self(), :poll, @error_backoff)
        {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  # Helpers
  defp get_updates(base, offset) do
    url = "#{base}/getUpdates?timeout=#{@get_updates_timeout}&offset=#{offset}"

    case HTTPoison.get(url, [], recv_timeout: (@get_updates_timeout + 5) * 1_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true, "result" => result}} -> {:ok, result}
          {:ok, other} -> {:error, other}
          err -> {:error, err}
        end

      {:ok, resp} -> {:error, resp}
      {:error, err} -> {:error, err}
    end
  end

  defp handle_update(base, %{"message" => message}) do
    chat_id = get_in(message, ["chat", "id"]) || get_in(message, [:chat, :id])
    text = get_in(message, ["text"]) || ""

    case String.trim(text) do
      "/start" ->
        send_message(base, chat_id, "Cześć! Jestem botem opartym o GenServer.")

      msg when msg != "" ->
        send_message(base, chat_id, "Echo: " <> msg)

      _ ->
        :ok
    end
  end
  defp handle_update(_base, _other), do: :ok

  defp send_message(base, chat_id, text) do
    url = "#{base}/sendMessage"
    body = Jason.encode!(%{"chat_id" => chat_id, "text" => text})
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> :ok
      {:ok, resp} -> Logger.warn("Nieoczekiwana odpowiedź przy wysyłaniu wiadomości: #{inspect(resp)}")
      {:error, err} -> Logger.error("Błąd wysyłania wiadomości: #{inspect(err)}")
    end
  end
end

# Uruchomienie tego pliku bez mieszania do aplikacji OTP
if function_exported?(Mix, :env, 0) do
  # Jeśli uruchamiane wewnątrz projektu Mix - uruchom GenServer i zatrzymaj main thread
  {:ok, _pid} = PollingBot.start_link()
  # Zapobiegaj zakończeniu procesu nadrzędnego
  :timer.sleep(:infinity)
else
  # When running as plain elixir script, still start the GenServer
  {:ok, _pid} = PollingBot.start_link()
  :timer.sleep(:infinity)
end
