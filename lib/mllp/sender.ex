defmodule MLLP.Sender do
  use GenServer
  require Logger

  alias MLLP.{Envelope, Ack}

  defstruct socket: nil,
            ip_address: {0, 0, 0, 0},
            port: 0,
            messages_sent: 0,
            failures: 0

  @max_failures 10

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
    GenServer.call(pid, {:send, wrapped_message}, 30_000)
  end

  def get_messages_sent(pid) do
    GenServer.call(pid, :get_messages_sent_count)
  end

  ## GenServer callbacks
  def init({ip_address, port}) do
    state = %State{ip_address: ip_address, port: port}
    {:ok, state}
  end

  def log_message(state, msg) do
    text = get_connection_string(state) <> "#{inspect(msg)}"
    Logger.warn(text)
  end

  def get_connection_string(state) do
    "Connection: #{state.ip_address |> Tuple.to_list() |> Enum.join(".")}:#{state.port} "
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


  #  def handle_call(:connect, _from, state) do
#    :gen_tcp.connect(state.ip_address, state.port, [:binary, {:packet, 0}, {:active, false}])
#    |> case do
#      {:ok, socket} ->
#        {:reply, :ok, %State{state | socket: socket}}
#
#      {:error, reason} ->
#        new_state = %{state | failures: 1}
#        log_message(new_state, reason)
#        {:reply, new_state, 1000}
#    end
#  end

  def handle_call(:close, _from, state) do
    :ok = :gen_tcp.close(state.socket)
    {:reply, :ok, %State{}}
  end

  def handle_call({:send, message}, _from, %State{socket: nil} = state) do
    Logger.warn("Cannot send to nil socket")
    {:reply, {:ok, :application_error}, state}
  end

  def handle_call({:send, message}, _from, state) do
    Logger.warn("#{inspect(state.socket)}")

    :gen_tcp.send(state.socket, message)
    |> case do
      :ok ->
        reply = receive_ack_for_message(state.socket, message)
        {:reply, reply, %State{state | messages_sent: state.messages_sent + 1}}

      {:error, error_type} ->
       Logger.warn("Failed to send message. Code #{error_type}")
        reply = {:ok, :application_error}

        {:reply, reply, state}
    end

  end

  def handle_call(:get_messages_sent_count, _reply, state) do
    {:reply, state.messages_sent, state}
  end

#  def handle_info({:tcp_closed, _socket}, state) do
#    case :gen_tcp.connect(state.host, state.port, []) do
#      {:ok, _socket} ->
#        new_state = %{state | failure_count: 0}
#        new_state.on_connect.(new_state)
#        {:noreply, new_state}
#
#      {:error, _reason} ->
#        new_state = %{state | failure_count: 1}
#        new_state.on_disconnect.(new_state)
#        {:noreply, new_state, 1000}
#    end
#  end
#
#  def handle_info(:timeout, state = %State{failure_count: failure_count}) do
#    if failure_count <= @max_retries do
#      case :gen_tcp.connect(state.host, state.port, []) do
#        {:ok, _socket} ->
#          new_state = %{state | failure_count: 0}
#          new_state.on_connect.(new_state)
#          {:noreply, new_state}
#
#        {:error, _reason} ->
#          new_state = %{state | failure_count: failure_count + 1}
#          new_state.on_disconnect.(new_state)
#          {:noreply, new_state, @retry_interval}
#      end
#    else
#      state.on_failure.(state)
#      {:stop, :max_retry_exceeded, state}
#    end
#  end

# todo parse partial or more msg
  defp receive_ack_for_message(socket, message) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, raw_ack} ->
        ack = raw_ack |> Envelope.unwrap_message()
        unwrapped_message = message |> Envelope.unwrap_message()
        Ack.verify_ack_against_message(unwrapped_message, ack)
    end
  end
end
