defmodule MLLP.Sender do
  use GenServer
  require Logger

  alias MLLP.{Envelope, Ack}

  defstruct socket: nil,
            ip_address: {0, 0, 0, 0},
            port: 0,
            messages_sent: 0,
            retries: 0

  alias __MODULE__, as: State

  ## API
  def start_link({ip_address, port}) do
    GenServer.start_link(__MODULE__, {ip_address, port})
  end

  def connect(pid) do
    GenServer.call(pid, :connect)
  end

  def close(pid) do
    GenServer.call(pid, :close)
  end

  def send_message(pid, message) do
    wrapped_message = Envelope.wrap_message(message)
    Logger.warn("out---:\n#{wrapped_message}\n")
    GenServer.call(pid, {:send, wrapped_message}, 30_000)
  end

  def get_messages_sent(pid) do
    GenServer.call(pid, :get_messages_sent_count)
  end

  #  def output(message) do
  #
  #  end

  ## GenServer callbacks
  def init({ip_address, port}) do
    state = %State{ip_address: ip_address, port: port}
    {:ok, state}
  end

  def handle_call(:connect, _from, state) do
    :gen_tcp.connect(state.ip_address, state.port, [:binary, {:packet, 0}, {:active, false}])
    |> case do
      {:ok, socket} ->
        {:reply, :ok, %State{state | socket: socket}}

      {:error, :econnrefused} ->
        {:reply,
         {:error,
          %{
            type: :econnrefused,
            message:
              "The connection to #{state.ip_address |> Tuple.to_list() |> Enum.join(".")}:#{
                state.port
              } was refused."
          }}, state}
    end
  end

  def handle_call(:close, _from, state) do
    :ok = :gen_tcp.close(state.socket)
    {:reply, :ok, %State{}}
  end

  def handle_call({:send, message}, _from, state) do
    :gen_tcp.send(state.socket, message)
    reply = receive_ack_for_message(state.socket, message)
    {:reply, reply, %State{state | messages_sent: state.messages_sent + 1}}
  end

  def handle_call(:get_messages_sent_count, _reply, state) do
    {:reply, state.messages_sent, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    case :gen_tcp.connect(state.host, state.port, []) do
      {:ok, _socket} ->
        new_state = %{state | failure_count: 0}
        new_state.on_connect.(new_state)
        {:noreply, new_state}
      {:error, _reason} ->
        new_state = %{state | failure_count: 1}
        new_state.on_disconnect.(new_state)
        {:noreply, new_state, @retry_interval}
    end
  end


  def handle_info(:timeout, state = %State{failure_count: failure_count}) do
    if failure_count <= @max_retries do
      case :gen_tcp.connect(state.host, state.port, []) do
        {:ok, _socket} ->
          new_state = %{state | failure_count: 0}
          new_state.on_connect.(new_state)
          {:noreply, new_state}
        {:error, _reason} ->
          new_state = %{state | failure_count: failure_count + 1}
          new_state.on_disconnect.(new_state)
          {:noreply, new_state, @retry_interval}
      end
    else
      state.on_failure.(state)
      {:stop, :max_retry_exceeded, state}
    end
  end

#  defp opts_to_initial_state(opts) do
#    host = Keyword.get(opts, :host, "localhost") |> String.to_char_list
#    port = Keyword.fetch!(opts, :port)
#    %State{host: host, port: port}
#  end

  defp receive_ack_for_message(socket, message) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, raw_ack} ->
        ack = raw_ack |> Envelope.unwrap_message()
        Logger.warn("ack---:\n#{inspect(message)}\n")
        Logger.warn("msg---:\n#{inspect(message)}\n")
        unwrapped_message = message |> Envelope.unwrap_message()
        Ack.verify_ack_against_message(unwrapped_message, ack)
    end
  end
end
