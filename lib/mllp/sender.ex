defmodule MLLP.SenderContract do
  @type error_type :: :connect_failure | :send_error | :recv_error
  @type error_reason :: :closed | :timeout | :no_socket | :inet.posix()

  @type sender_error :: %{type: error_type(), reason: error_reason()}

  @callback send_hl7_and_receive_ack(
              pid :: pid,
              payload :: HL7.Message.t(),
              timeout :: non_neg_integer()
            ) ::
              MLLP.Ack.ack_verification_result() | {:error, sender_error()}
  @callback send_hl7(pid :: pid, payload :: HL7.Message.t()) ::
              {:ok, :sent} | {:error, sender_error()}
  @callback send_non_hl7_and_receive_reply(
              pid :: pid,
              payload :: String.t(),
              timeout :: non_neg_integer()
            ) ::
              {:ok, String.t()} | {:error, sender_error()}
  @callback send_non_hl7(pid :: pid, payload :: String.t()) ::
              {:ok, :sent} | {:error, sender_error()}
  @callback send_raw_and_receive_reply(
              pid :: pid,
              payload :: String.t(),
              timeout :: non_neg_integer()
            ) ::
              {:ok, String.t()} | {:error, sender_error()}
  @callback send_raw(pid :: pid, payload :: String.t()) :: {:ok, :sent} | {:error, sender_error()}
end

defmodule MLLP.Sender do
  use GenServer
  require Logger

  alias MLLP.{Envelope, Ack, SenderContract, TCP, TLS}

  @behaviour SenderContract

  @type pid_ref :: atom | pid | {atom, any} | {:via, atom, any}
  @type ip_address ::
          atom
          | charlist
          | {:local, binary | charlist}
          | {byte, byte, byte, byte}
          | {char, char, char, char, char, char, char, char}

  @type t :: %MLLP.Sender{
          socket: any(),
          address: ip_address(),
          port: char(),
          pending_reconnect: reference() | nil,
          pid: pid() | nil,
          telemetry_module: module() | nil,
          tcp: module() | nil,
          tls_options: Keyword.t()
        }

  defstruct socket: nil,
            address: {127, 0, 0, 1},
            port: 0,
            pending_reconnect: nil,
            pid: nil,
            telemetry_module: nil,
            tcp: nil,
            tls_options: []

  alias __MODULE__, as: State

  ## API
  @spec start_link(
          address ::
            :inet.ip4_address()
            | :inet.ip6_address()
            | String.t(),
          port :: non_neg_integer(),
          options :: [keyword()]
        ) :: {:ok, pid()}

  def start_link(address, port, options \\ []) do
    checked_address =
      address
      |> case do
        {_, _, _, _} ->
          address

        {_, _, _, _, _, _, _, _} ->
          address

        value when is_binary(value) ->
          value |> String.to_charlist()
      end

    GenServer.start_link(__MODULE__, [address: checked_address, port: port] ++ options)
  end

  @spec is_connected?(pid :: pid()) :: boolean()
  def is_connected?(pid) do
    GenServer.call(pid, :is_connected)
  end

  @spec reconnect(pid :: pid()) :: :ok
  def reconnect(pid) do
    GenServer.call(pid, :reconnect)
  end

  @spec send_hl7_and_receive_ack(
          pid :: pid,
          payload :: HL7.Message.t(),
          timeout :: non_neg_integer()
        ) ::
          MLLP.Ack.ack_verification_result() | {:error, SenderContract.sender_error()}
  def send_hl7_and_receive_ack(
        pid,
        %HL7.Message{} = payload,
        timeout \\ 5000
      ) do
    GenServer.call(pid, {:send_hl7_and_receive_ack, payload |> to_string()}, timeout + 1000)
  end

  @spec send_hl7(pid :: pid, payload :: HL7.Message.t()) ::
          {:ok, :sent} | {:error, SenderContract.sender_error()}
  def send_hl7(pid, %HL7.Message{} = payload) when is_pid(pid) do
    GenServer.call(pid, {:send_hl7, payload |> to_string()})
  end

  @spec send_non_hl7_and_receive_reply(
          pid :: pid,
          payload :: String.t(),
          timeout :: non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, SenderContract.sender_error()}
  def send_non_hl7_and_receive_reply(
        pid,
        payload,
        timeout \\ 5000
      ) do
    options = [expect_reply: true, wrap_message: true, reply_timout: timeout]

    GenServer.call(pid, {:send, payload, options}, timeout + 1000)
  end

  @spec send_non_hl7(pid :: pid, payload :: String.t()) ::
          {:ok, :sent} | {:error, SenderContract.sender_error()}
  def send_non_hl7(
        pid,
        payload
      ) do
    options = [expect_reply: false, wrap_message: true]

    GenServer.call(pid, {:send, payload, options})
  end

  @spec send_raw_and_receive_reply(
          pid :: pid,
          payload :: String.t(),
          timeout :: non_neg_integer()
        ) ::
          {:ok, String.t()} | {:error, SenderContract.sender_error()}
  def send_raw_and_receive_reply(
        pid,
        payload,
        timeout \\ 5000
      ) do
    options = [expect_reply: true, wrap_message: false, reply_timout: timeout]

    GenServer.call(pid, {:send, payload, options}, timeout + 1000)
  end

  @spec send_raw(pid :: pid, payload :: String.t()) ::
          {:ok, :sent} | {:error, SenderContract.sender_error()}
  def send_raw(pid, payload) do
    options = [expect_reply: false, wrap_message: false]

    GenServer.call(pid, {:send, payload, options})
  end

  @spec stop(pid :: pid()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  @spec send_message(pid_ref(), binary()) :: any()
  def send_message(pid, message) do
    wrapped_message = Envelope.wrap_message(message)
    GenServer.call(pid, {:send, wrapped_message}, 30_000)
  end

  ## GenServer callbacks
  # ===================
  # GenServer callbacks
  # ===================

  @spec init(Keyword.t()) :: {:ok, MLLP.Sender.t()}
  def init(options) do
    address = Keyword.fetch!(options, :address)

    port = Keyword.fetch!(options, :port)

    telemetry_module = Keyword.get(options, :telemetry_module, MLLP.DefaultTelemetry)
    tls_options = Keyword.get(options, :tls, [])
    socket_module = if tls_options == [], do: TCP, else: TLS

    state =
      %State{
        pid: self(),
        address: address,
        port: port,
        telemetry_module: telemetry_module,
        tcp: socket_module,
        tls_options: tls_options
      }
      |> Map.update!(:tcp, fn old_tcp -> Keyword.get(options, :tcp, old_tcp) end)
      |> attempt_connection()

    {:ok, state}
  end

  def handle_call(:is_connected, _reply, state) do
    {:reply, (state.socket && !state.pending_reconnect) == true, state}
  end

  def handle_call(:reconnect, _from, state) do
    state1 = stop_connection(state, nil, "reconnect command")
    {:reply, :ok, state1}
  end

  def handle_call(_, _from, %State{socket: nil} = state) do
    telemetry(
      :status,
      %{status: :disconnected, error: :no_socket, context: "MLLP.Sender disconnected failure"},
      state
    )

    {:reply, {:error, %{type: :connect_failure, reason: :no_socket}}, state}
  end

  def handle_call({:send, message, options}, _from, state) do
    telemetry(:sending, %{}, state)

    payload =
      if Keyword.get(options, :wrap_message) do
        message |> MLLP.Envelope.wrap_message()
      else
        message
      end

    case state.tcp.send(state.socket, payload) do
      :ok ->
        if Keyword.get(options, :expect_reply) do
          case receive_reply(state, Keyword.get(options, :reply_timout)) do
            {:ok, _} = reply ->
              telemetry(:received, %{response: reply}, state)
              {:reply, reply, state}

            {:error, reason} ->
              handle_recv_error(state, reason)
          end
        else
          {:reply, {:ok, :sent}, state}
        end

      {:error, reason} ->
        handle_send_error(state, reason)
    end
  end

  def handle_call({:send_hl7_and_receive_ack, message}, _from, state) do
    telemetry(:sending, %{}, state)

    payload = message |> MLLP.Envelope.wrap_message()

    case state.tcp.send(state.socket, payload) do
      :ok ->
        case receive_hl7_ack_for_message(state, payload) do
          {:ok, reply} ->
            telemetry(:received, %{response: reply}, state)
            {:reply, reply, state}

          {:error, reason} ->
            handle_recv_error(state, reason)
        end

      {:error, reason} ->
        handle_send_error(state, reason)
    end
  end

  def handle_call({:send_hl7, message}, _from, state) do
    telemetry(:sending, %{}, state)

    payload = message |> MLLP.Envelope.wrap_message()

    case state.tcp.send(state.socket, payload) do
      :ok ->
        reply = {:ok, :sent}

        telemetry(:received, %{response: reply}, state)
        {:reply, reply, state}

      {:error, reason} ->
        handle_send_error(state, reason)
    end
  end

  def handle_call(_, _from, %State{socket: nil} = state) do
    telemetry(
      :status,
      %{status: :disconnected, error: :no_socket, context: "MLLP.Sender disconnected failure"},
      state
    )

    {:reply, {:error, %{type: :connect_failure, reason: :no_socket}}, state}
  end

  def handle_info(:timeout, state) do
    new_state =
      state
      |> stop_connection(:timeout, "timeout message")
      |> attempt_connection()

    {:noreply, new_state}
  end

  def terminate(reason, state) do
    Logger.error("Sender socket terminated. Reason: #{inspect(reason)} State: %{inspect state}")
    stop_connection(state, reason, "process terminated")
  end

  defp handle_send_error(state, error) do
    telemetry(
      :status,
      %{status: :disconnected, error: error, context: "send message failure"},
      state
    )

    new_state = maintain_reconnect_timer(state)
    reply = {:error, %{type: :send_failure, reason: error}}
    {:reply, reply, new_state}
  end

  defp handle_recv_error(state, error) do
    telemetry(
      :status,
      %{status: :disconnected, error: error, context: "receive ACK failure"},
      state
    )

    new_state = maintain_reconnect_timer(state)
    reply = {:error, %{type: :recv_failure, reason: error}}
    {:reply, reply, new_state}
  end

  defp stop_connection(%State{} = state, error, context) do
    if state.socket != nil do
      telemetry(
        :status,
        %{status: :disconnected, error: error, context: context},
        state
      )

      state.tcp.close(state.socket)
    end

    ensure_pending_reconnect_cancelled(state)
  end

  defp ensure_pending_reconnect_cancelled(%{pending_reconnect: nil} = state), do: state

  defp ensure_pending_reconnect_cancelled(state) do
    :ok = Process.cancel_timer(state.pending_reconnect, info: false)
    %{state | pending_reconnect: nil}
  end

  defp attempt_connection(%State{} = state) do
    telemetry(:status, %{status: :connecting}, state)

    options =
      [:binary, {:packet, 0}, {:active, false}] ++
        state.tls_options

    state.tcp.connect(
      state.address,
      state.port,
      options,
      2000
    )
    |> case do
      {:ok, socket} ->
        if state.pending_reconnect != nil do
          :ok = Process.cancel_timer(state.pending_reconnect, info: false)
        end

        telemetry(:status, %{status: :connected}, state)
        %{state | socket: socket, pending_reconnect: nil}

      {:error, reason} ->
        telemetry(
          :status,
          %{status: :disconnected, error: reason, context: "connect failure"},
          state
        )

        maintain_reconnect_timer(state)
    end
  end

  defp maintain_reconnect_timer(state) do
    ref = state.pending_reconnect || Process.send_after(self(), :timeout, 1000)
    %State{state | pending_reconnect: ref}
  end

  defp receive_hl7_ack_for_message(state, message) do
    case state.tcp.recv(state.socket, 0) do
      {:ok, raw_ack} ->
        ack = raw_ack |> Envelope.unwrap_message()
        unwrapped_message = message |> Envelope.unwrap_message()

        reply = Ack.verify_ack_against_message(unwrapped_message, ack)
        {:ok, reply}

      {:error, _} = err ->
        err
    end
  end

  defp receive_reply(state, reply_timout) do
    case state.tcp.recv(state.socket, 0, reply_timout) do
      {:ok, raw_reply} ->
        {:ok, raw_reply}

      {:error, _} = err ->
        err
    end
  end

  defp telemetry(_event_name, _measurements, %State{telemetry_module: nil} = _metadata) do
    :ok
  end

  defp telemetry(event_name, measurements, %State{telemetry_module: telemetry_module} = metadata) do
    telemetry_module.execute([:sender, event_name], add_timestamps(measurements), metadata)
  end

  defp add_timestamps(measurements) do
    measurements
    |> Map.put(:monotonic, :erlang.monotonic_time())
    |> Map.put(:utc_datetime, DateTime.utc_now())
  end
end
