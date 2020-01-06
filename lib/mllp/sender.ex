defmodule MLLP.SenderContract do
  @type sender_error ::
          :unspecified_error
          | :reply_timeout_exceeded
          | :not_connected
          | :tcp_error

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

  alias MLLP.{Envelope, Ack, SenderContract, TCP}

  @behaviour SenderContract

  defstruct socket: nil,
            ip_address: {0, 0, 0, 0},
            port: 0,
            pending_reconnect: nil,
            pid: nil,
            telemetry_module: nil,
            tcp: TCP

  alias __MODULE__, as: State

  ## API
  def start_link({ip_address, port}, options \\ []) do
    GenServer.start_link(__MODULE__, [ip_address: ip_address, port: port] ++ options)
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

  # ===================
  # GenServer callbacks
  # ===================

  def init(options) do
    ip_address = Keyword.fetch!(options, :ip_address)
    port = Keyword.fetch!(options, :port)

    telemetry_module = Keyword.get(options, :telemetry_module, MLLP.DefaultTelemetry)

    state =
      %State{pid: self(), ip_address: ip_address, port: port, telemetry_module: telemetry_module}
      |> Map.update!(:tcp, fn old_tcp -> Keyword.get(options, :tcp, old_tcp) end)
      |> attempt_connection()

    {:ok, state}
  end

  def handle_call(:is_connected, _reply, state) do
    {:reply, (state.socket && !state.pending_reconnect) == true, state}
  end

  def handle_call(:reconnect, _from, state) do
    stop_connection(state, nil, "reconnect command")
    {:reply, :ok, state}
  end

  def handle_call(_, _from, %State{socket: nil} = state) do
    telemetry(
      :status,
      %{status: :disconnected, error: :nil_socket, context: "MLLP.Sender disconnected failure"},
      state
    )

    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send, message, options}, _from, state) do
    telemetry(:sending, %{}, state)

    payload =
      if Keyword.get(options, :wrap_message) do
        message |> MLLP.Envelope.wrap_message()
      else
        message
      end

    state.tcp.send(state.socket, payload)
    |> case do
      :ok ->
        reply =
          if Keyword.get(options, :expect_reply) do
            receive_reply(state, Keyword.get(options, :reply_timout))
          else
            {:ok, :sent}
          end

        telemetry(:received, %{response: reply}, state)
        {:reply, reply, state}

      {:error, reason} ->
        telemetry(
          :status,
          %{status: :disconnected, error: reason, context: "send message failure"},
          state
        )

        new_state = maintain_reconnect_timer(state)
        reply = {:error, :send_message_failure}
        {:reply, reply, new_state}
    end
  end

  def handle_call({:send_hl7_and_receive_ack, message}, _from, state) do
    telemetry(:sending, %{}, state)

    payload = message |> MLLP.Envelope.wrap_message()

    state.tcp.send(state.socket, payload)
    |> case do
      :ok ->
        reply = receive_hl7_ack_for_message(state, payload)

        telemetry(:received, %{response: reply}, state)
        {:reply, reply, state}

      {:error, reason} ->
        telemetry(
          :status,
          %{status: :disconnected, error: reason, context: "send message failure"},
          state
        )

        new_state = maintain_reconnect_timer(state)
        reply = {:error, :send_message_failure}
        {:reply, reply, new_state}
    end
  end

  def handle_call({:send_hl7, message}, _from, state) do
    telemetry(:sending, %{}, state)

    payload = message |> MLLP.Envelope.wrap_message()

    state.tcp.send(state.socket, payload)
    |> case do
      :ok ->
        reply = {:ok, :sent}

        telemetry(:received, %{response: reply}, state)
        {:reply, reply, state}

      {:error, reason} ->
        telemetry(
          :status,
          %{status: :disconnected, error: reason, context: "send message failure"},
          state
        )

        new_state = maintain_reconnect_timer(state)
        reply = {:error, :send_message_failure}
        {:reply, reply, new_state}
    end
  end

  def handle_info({:tcp_closed, _socket}, state) do
    telemetry(:status, %{status: :disconnected, error: :tcp_closed}, state)
    {:noreply, maintain_reconnect_timer(state)}
  end

  def handle_info({:tcp_error, _, reason}, state) do
    telemetry(:status, %{status: :disconnected, error: :tcp_error, context: reason}, state)
    {:stop, reason, state}
  end

  def handle_info(:timeout, state) do
    telemetry(
      :status,
      %{status: :disconnected, error: :timeout, context: "timeout message"},
      state
    )

    new_state =
      %State{state | pending_reconnect: nil}
      |> attempt_connection()

    {:noreply, new_state}
  end

  def terminate(reason, state) do
    Logger.error("Sender socket terminated. Reason: #{inspect(reason)} State: %{inspect state}")
    stop_connection(state, reason, "process terminated")
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

    if state.pending_reconnect, do: Process.cancel_timer(state.pending_reconnect)
  end

  defp attempt_connection(%State{} = state) do
    telemetry(:status, %{status: :connecting}, state)

    state.tcp.connect(
      state.ip_address,
      state.port,
      [:binary, {:packet, 0}, {:active, false}],
      2000
    )
    |> case do
      {:ok, socket} ->
        if state.pending_reconnect != nil do
          Process.cancel_timer(state.pending_reconnect)
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

        Ack.verify_ack_against_message(unwrapped_message, ack)

      {:error, reason} ->
        telemetry(
          :status,
          %{status: :disconnected, error: reason, context: "receive ACK failure"},
          state
        )

        maintain_reconnect_timer(state)
        {:error, reason}
    end
  end

  defp receive_reply(state, reply_timout) do
    case state.tcp.recv(state.socket, 0, reply_timout) do
      {:ok, raw_reply} ->
        {:ok, raw_reply}

      {:error, reason} ->
        telemetry(
          :status,
          %{status: :disconnected, error: reason, context: "receive ACK failure"},
          state
        )

        maintain_reconnect_timer(state)
        {:error, reason}
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
