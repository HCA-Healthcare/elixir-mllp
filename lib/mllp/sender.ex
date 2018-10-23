defmodule MLLP.Sender do
  use GenServer
  require Logger

  alias MLLP.{Envelope, Ack}

  defstruct socket: nil,
            ip_address: {0, 0, 0, 0},
            port: 0,
            messages_sent: 0,
            failures: 0,
            pending_reconnect: nil

  alias __MODULE__, as: State

  ## API
  def start_link({ip_address, port}) do
    GenServer.start_link(__MODULE__, {ip_address, port})
  end

  def send_message(pid, message) do
    wrapped_message = Envelope.wrap_message(message)
    GenServer.call(pid, {:send, wrapped_message}, 30_000)
  end

  def get_messages_sent(pid) do
    GenServer.call(pid, :get_messages_sent_count)
  end

  ## GenServer callbacks
  def init({ip_address, port}) do
    state = attempt_connection(%State{ip_address: ip_address, port: port})
    {:ok, state}
  end

  def handle_call({:send, _message}, _from, %State{socket: nil} = state) do
    log_message(state, " cannot send to nil socket")
    {:reply, {:ok, :application_error}, state}
  end

  def handle_call({:send, message}, _from, state) do
    :gen_tcp.send(state.socket, message)
    |> case do
      :ok ->
        reply = receive_ack_for_message(state, message)
        {:reply, reply, %State{state | messages_sent: state.messages_sent + 1}}

      {:error, reason} ->
        log_message(state, " could not send message, reason: " <> "#{reason}")
        new_state = maintain_reconnect_timer(state)
        reply = {:ok, :application_error}
        {:reply, reply, new_state}
    end
  end

  def handle_call(:get_messages_sent_count, _reply, state) do
    {:reply, state.messages_sent, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    new_state = maintain_reconnect_timer(state)
    {:noreply, new_state}
  end

  def handle_info(:timeout, state) do
    new_state =
      %State{state | pending_reconnect: nil}
      |> attempt_connection()

    {:noreply, new_state}
  end

  defp log_message(state, msg) do
    text = "MLLP Sender: " <> get_connection_string(state) <> msg
    Logger.warn(text)
  end

  defp get_connection_string(state) do
    "Connection: #{state.ip_address |> Tuple.to_list() |> Enum.join(".")}:#{state.port} "
  end

  defp attempt_connection(%State{failures: failures} = state) do
    :gen_tcp.connect(
      state.ip_address,
      state.port,
      [:binary, {:packet, 0}, {:active, false}],
      2000
    )
    |> case do
      {:ok, socket} ->
        if state.pending_reconnect do
          Process.cancel_timer(state.pending_reconnect)
        end

        new_state = %{state | failures: 0, socket: socket, pending_reconnect: nil}
        log_message(new_state, " connected.")
        new_state

      {:error, reason} ->
        new_state = %{state | failures: failures + 1}
        log_message(new_state, " could not connect, reason: " <> "#{reason}")
        maintain_reconnect_timer(new_state)
    end
  end

  defp maintain_reconnect_timer(state) do
    ref = state.pending_reconnect || Process.send_after(self(), :timeout, 1000)
    %State{state | pending_reconnect: ref}
  end

  defp receive_ack_for_message(state, message) do
    case :gen_tcp.recv(state.socket, 0) do
      {:ok, raw_ack} ->
        ack = raw_ack |> Envelope.unwrap_message()
        unwrapped_message = message |> Envelope.unwrap_message()
        Ack.verify_ack_against_message(unwrapped_message, ack)

      {:error, reason} ->
        log_message(state, " could not receive ack, reason: " <> "#{reason}")
        maintain_reconnect_timer(state)
        {:ok, :application_error}
    end
  end
end
