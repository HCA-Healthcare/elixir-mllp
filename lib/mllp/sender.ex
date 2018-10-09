defmodule MLLP.Sender do
  use GenServer
  require Logger

  alias MLLP.{Envelope, Ack}

  defstruct socket: nil, ip_address: {0, 0, 0, 0}, port: 0, messages_sent: 0
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
    |> case do
      :ok ->
        reply = receive_ack_for_message(state.socket, message)
        {:reply, reply, %State{state | messages_sent: state.messages_sent + 1}}

      {:error, error_type} ->
        reply =
          {:error, %{type: error_type, message: "Failed to send message. Code #{error_type}"}}

        {:reply, reply, state}
    end
  end

  def handle_call(:get_messages_sent_count, _reply, state) do
    {:reply, state.messages_sent, state}
  end

  defp receive_ack_for_message(socket, message) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, raw_ack} ->
        ack = raw_ack |> Envelope.unwrap_message()
        unwrapped_message = message |> Envelope.unwrap_message()
        Ack.verify_ack_against_message(unwrapped_message, ack)
    end
  end
end
