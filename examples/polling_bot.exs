# Przykładowy bot Telegram (polling) - examples/polling_bot.exs
#
# Wymagania:
# - Ustaw zmienną środowiskową TELEGRAM_BOT_TOKEN z tokenem bota
# - Dodaj do mix.exs zależności: {:httpoison, "~> 1.8"}, {:jason, "~> 1.2"}
#   i uruchom `mix deps.get` przed uruchomieniem skryptu
#
# Uruchomienie:
#   elixir examples/polling_bot.exs
#
# Ten skrypt pokazuje prosty mechanizm pollingowy: pobiera updates, reaguje na /start i echo.

defmodule PollingBot do
  @moduledoc """
  Prosty polling bot dla Telegrama (przykład). Nie używa żadnych specyficznych modułów z repozytorium —
  jest to minimalny, samodzielny przykład pokazujący jak wysyłać/odbierać wiadomości przez API.
  """

  def run do
    token = System.get_env("TELEGRAM_BOT_TOKEN") || raise "Ustaw zmienną środowiskową TELEGRAM_BOT_TOKEN"
    base = "https://api.telegram.org/bot#{token}"
    loop(base, 0)
  end

  defp loop(base, offset) do
    case get_updates(base, offset) do
      {:ok, updates} when is_list(updates) ->
        new_offset = Enum.reduce(updates, offset, fn upd, acc ->
          handle_update(base, upd)
          update_id = get_in(upd, ["update_id"]) || 0
          max(acc, update_id + 1)
        end)

        # krótka pauza między zapytaniami
        :timer.sleep(1000)
        loop(base, new_offset)

      {:error, reason} ->
        IO.puts("Błąd pobierania updates: #{inspect(reason)} — spróbuję ponownie za 5s")
        :timer.sleep(5_000)
        loop(base, offset)
    end
  end

  defp get_updates(base, offset) do
    url = "#{base}/getUpdates?timeout=10&offset=#{offset}"

    case HTTPoison.get(url, [], recv_timeout: 15_000) do
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
        send_message(base, chat_id, "Cześć! Jestem przykładowym botem (polling).")

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
      {:ok, resp} -> IO.puts("Nieoczekiwana odpowiedź: #{inspect(resp)}")
      {:error, err} -> IO.puts("Błąd wysyłania wiadomości: #{inspect(err)}")
    end
  end
end

# Start
PollingBot.run()
