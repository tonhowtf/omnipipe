defmodule Omnipipe do
  @moduledoc "TCP relay that pairs two connections by code and pipes bytes between them."

  @port String.to_integer(System.get_env("PORT") || "9009")
  @room_ttl_ms 600_000
  @cleanup_interval_ms 60_000

  def start do
    :ets.new(:rooms, [:named_table, :set, :protected])
    {:ok, listen} = :gen_tcp.listen(@port, [:binary, active: false, reuseaddr: true, packet: :line])
    IO.puts("[omnipipe] listening on :#{@port}")
    spawn(fn -> cleanup_loop() end)
    accept_loop(listen)
  end

  defp accept_loop(listen) do
    {:ok, socket} = :gen_tcp.accept(listen)
    spawn(fn -> handle(socket) end)
    accept_loop(listen)
  end

  defp handle(socket) do
    with {:ok, line} <- :gen_tcp.recv(socket, 0, 30_000),
         [cmd, code] <- String.trim(line) |> String.split(" ", parts: 2) do
      case cmd do
        "SEND" -> handle_send(socket, code)
        "RECV" -> handle_recv(socket, code)
        _ -> send_error(socket, "bad_command")
      end
    else
      _ -> :gen_tcp.close(socket)
    end
  end

  defp handle_send(socket, code) do
    case :ets.insert_new(:rooms, {code, socket, self(), System.monotonic_time(:millisecond)}) do
      true ->
        :gen_tcp.send(socket, "WAIT\n")
        IO.puts("[omnipipe] room #{code}")
        await_pair(socket, code)

      false ->
        send_error(socket, "room_exists")
    end
  end

  defp await_pair(socket, code) do
    receive do
      {:paired, receiver} ->
        :gen_tcp.send(socket, "READY\n")
        :gen_tcp.send(receiver, "READY\n")
        :inet.setopts(socket, packet: :raw)
        :inet.setopts(receiver, packet: :raw)
        relay(socket, receiver, code)

      :expire ->
        :gen_tcp.close(socket)
    end
  end

  defp handle_recv(socket, code) do
    case :ets.lookup(:rooms, code) do
      [{^code, _sender, pid, _ts}] ->
        case :gen_tcp.controlling_process(socket, pid) do
          :ok -> send(pid, {:paired, socket})
          {:error, reason} -> send_error(socket, "handoff_failed: #{reason}")
        end

      [] ->
        send_error(socket, "room_not_found")
    end
  end

  defp relay(a, b, code) do
    parent = self()
    spawn(fn -> copy(a, b); send(parent, :half_closed) end)
    spawn(fn -> copy(b, a); send(parent, :half_closed) end)
    receive do :half_closed -> :ok end
    :gen_tcp.close(a)
    :gen_tcp.close(b)
    :ets.delete(:rooms, code)
    IO.puts("[omnipipe] done #{code}")
  end

  defp copy(from, to) do
    with {:ok, data} <- :gen_tcp.recv(from, 0),
         :ok <- :gen_tcp.send(to, data) do
      copy(from, to)
    else
      _ -> :ok
    end
  end

  defp send_error(socket, reason) do
    :gen_tcp.send(socket, "ERROR #{reason}\n")
    :gen_tcp.close(socket)
  end

  defp cleanup_loop do
    Process.sleep(@cleanup_interval_ms)
    now = System.monotonic_time(:millisecond)

    for {code, _socket, pid, ts} <- :ets.tab2list(:rooms),
        now - ts > @room_ttl_ms do
      send(pid, :expire)
      :ets.delete(:rooms, code)
      IO.puts("[omnipipe] expired #{code}")
    end

    cleanup_loop()
  end
end

Omnipipe.start()