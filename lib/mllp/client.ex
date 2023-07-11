defmodule MLLP.ClientContract do
  @moduledoc """
  MLLP.ClientContract provides the behavior implemented by MLLP.Client. It may be useful
  for testing in your own application with tools such as [`Mox`](https://hexdocs.pm/mox/)
  """
  @type error_type :: :tcp_error | :send_error | :recv_error
  @type error_reason :: :closed | :timeout | :no_socket | :inet.posix()

  @type client_error :: MLLP.Client.Error.t()

  @type options :: [
          auto_reconnect_interval: non_neg_integer(),
          use_backoff: boolean(),
          backoff_max_seconds: integer(),
          reply_timeout: non_neg_integer() | :infinity,
          socket_opts: [:gen_tcp.option()],
          telemetry_module: nil,
          close_on_recv_error: boolean(),
          tls: [:ssl.tls_client_option()]
        ]

  @type send_options :: %{
          optional(:reply_timeout) => non_neg_integer() | :infinity
        }

  @callback send(
              pid :: pid,
              payload :: HL7.Message.t() | String.t(),
              options :: send_options(),
              timeout :: non_neg_integer() | :infinity
            ) ::
              {:ok, String.t()}
              | MLLP.Ack.ack_verification_result()
              | {:error, client_error()}

  @callback send_async(
              pid :: pid,
              payload :: HL7.Message.t() | String.t(),
              timeout :: non_neg_integer | :infinity
            ) ::
              {:ok, :sent}
              | {:error, client_error()}
end

defmodule MLLP.Client do
  @moduledoc """
  MLLP.Client provides a simple tcp client for sending and receiving data
  via [MLLP](https://www.hl7.org/documentcenter/public/wg/inm/mllp_transport_specification.PDF) over TCP.

  While MLLP is primarily used to send [HL7](https://en.wikipedia.org/wiki/Health_Level_7) messages,
  MLLP.Client can be used to send non-hl7 messages, such as XML.

  ## Connection Behaviour

  Upon successful start up via `start_link/4`, the  client will attempt to establish a connection to the given address
  on the provided port. If a connection can not be immediately established, the client will keep
  trying to establish a connection per the value of `:auto_reconnect_interval` which defaults to
  1 second. Therefore it is possible that before a connection is fully established, the caller
  may attempt to send a message which will result in `MLLP.Client.Error.t()` being returned containing
  the last error encountered in trying to establish a connection. Additionally, said behavour could be encountered
  at any point during life span of an MLLP.Client process if the connection becomes severed on either side.

  All connections, send, and receive failures will be logged as errors.

  ## Examples

  ### Sending messages as strings
  ```
  iex> MLLP.Receiver.start(dispatcher: MLLP.EchoDispatcher, port: 4090)
  {:ok,
  %{
    pid: #PID<0.2167.0>,
    port: 4090,
    receiver_id: #Reference<0.3312799297.2467299337.218126>
  }}
  iex> {:ok, client} = MLLP.Client.start_link("127.0.0.1", 4090)
  {:ok, #PID<0.369.0>}
  iex> msg = "MSH|^~\\&|MegaReg|XYZHospC|SuperOE|XYZImgCtr|20060529090131-0500|..."
  "MSH|^~\\&|MegaReg|XYZHospC|SuperOE|XYZImgCtr|20060529090131-0500|..."
  iex> MLLP.Client.send(client, msg)
  {:ok, "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^A01^ACK|..."}
  iex>
  ```

  ### Sending messages with `HL7.Message.t()`
  ```
  iex> MLLP.Receiver.start(dispatcher: MLLP.EchoDispatcher, port: 4090)
  {:ok,
  %{
    pid: #PID<0.2167.0>,
    port: 4090,
    receiver_id: #Reference<0.3312799297.2467299337.218126>
  }}
  iex> {:ok, client} = MLLP.Client.start_link("127.0.0.1", 4090)
  {:ok, #PID<0.369.0>}
  iex> msg = HL7.Message.new(HL7.Examples.wikipedia_sample_hl7())
  iex> MLLP.Client.send(client, msg)
  {:ok, :application_accept,
      %MLLP.Ack{
      acknowledgement_code: "AA",
      hl7_ack_message: nil,
      text_message: "A real MLLP message dispatcher was not provided"
  }}
  ```

  ### Using TLS

  ```
  iex> tls_opts = [
    cacertfile: "/path/to/ca_certificate.pem",
    verify: :verify_peer,
    certfile: "/path/to/server_certificate.pem",
    keyfile: "/path/to/private_key.pem"
  ]
  iex> MLLP.Receiver.start(dispatcher: MLLP.EchoDispatcher, port: 4090, tls: tls_opts)
  iex> {:ok, client} = MLLP.Client.start_link("localhost", 8154, tls: [verify: :verify_peer, cacertfile: "path/to/ca_certfile.pem"])
  iex> msg = HL7.Message.new(HL7.Examples.wikipedia_sample_hl7())
  iex> MLLP.Client.send(client, msg)
  {:ok, :application_accept,
      %MLLP.Ack{
      acknowledgement_code: "AA",
      hl7_ack_message: nil,
      text_message: "A real MLLP message dispatcher was not provided"
  }}
  ```
  """

  require Logger

  alias MLLP.{Envelope, Ack, ClientContract, TCP, TLS}

  @behaviour MLLP.ClientContract

  @behaviour :gen_statem

  @type pid_ref :: atom | pid | {atom, any} | {:via, atom, any}
  @type ip_address :: :inet.socket_address() | String.t()

  @type t :: %MLLP.Client{
          socket: any(),
          socket_address: String.t(),
          address: ip_address(),
          port: char(),
          auto_reconnect_interval: non_neg_integer(),
          pid: pid() | nil,
          telemetry_module: module() | nil,
          tcp: module() | nil,
          tls_opts: Keyword.t(),
          socket_opts: Keyword.t(),
          close_on_recv_error: boolean(),
          backoff: any(),
          caller: pid() | nil,
          receive_buffer: binary() | nil,
          context: atom()
        }

  defstruct socket: nil,
            socket_address: "127.0.0.1:0",
            auto_reconnect_interval: 1000,
            address: {127, 0, 0, 1},
            port: 0,
            pid: nil,
            telemetry_module: nil,
            tcp: nil,
            tcp_error: nil,
            host_string: nil,
            send_opts: %{},
            tls_opts: [],
            socket_opts: [],
            close_on_recv_error: true,
            backoff: nil,
            caller: nil,
            receive_buffer: nil,
            context: :connect

  alias __MODULE__, as: State

  ## API
  @doc false
  @spec format_error(term()) :: String.t()
  def format_error({:tls_alert, _} = err) do
    to_string(:ssl.format_error({:error, err}))
  end

  def format_error(:closed), do: "connection closed"
  def format_error(:timeout), do: "timed out"
  def format_error(:system_limit), do: "all available erlang emulator ports in use"

  def format_error(:invalid_reply) do
    "Invalid header received in server acknowledgment"
  end

  def format_error(posix) when is_atom(posix) do
    case :inet.format_error(posix) do
      'unknown POSIX error' ->
        inspect(posix)

      char_list ->
        to_string(char_list)
    end
  end

  def format_error(err) when is_binary(err), do: err

  def format_error(err), do: inspect(err)

  @doc """
  Starts a new MLLP.Client.

  MLLP.Client.start_link/4 will start a new MLLP.Client process.

  This function will raise a `ArgumentError` if an invalid `ip_address()` is provided.

  ## Options

  * `:use_backoff` - Specify if an exponential backoff should be used for connection. When an attempt
     to establish a connection fails, either post-init or at some point during the life span of the client,
     the backoff value will determine how often to retry a reconnection. Starts at 1 second and increases
     exponentially until reaching `backoff_max_seconds` seconds.  Defaults to `true`.

  * `:backoff_max_seconds` - Specify the max limit of seconds the backoff reconection attempt should take,
     defauls to 180 (3 mins).

  * `:auto_reconnect_interval` - Specify the interval between connection attempts. Specifically, if an attempt
     to establish a connection fails, either post-init or at some point during the life span of the client, the value
     of this option shall determine how often to retry a reconnection. Defaults to 1000 milliseconds.
     This option will only be used if `use_backoff` is set to `false`.

  * `:reply_timeout` - Optionally specify a timeout value for receiving a response. Must be a positive integer or
     `:infinity`. Defaults to 60 seconds.

  * `:socket_opts` -  A list of socket options as supported by [`:gen_tcp`](`:gen_tcp`).
     Note that `:binary`, `:packet`, and `:active` can not be overridden. Default options are enumerated below.
      - send_timeout: Defaults to 60 seconds

  * `:close_on_recv_error` - A boolean value which dictates whether the client socket will be
     closed when an error in receiving a reply is encountered, this includes timeouts.
     Setting this to `true` is usually the safest behaviour to avoid a "dead lock" situation between a
     client and a server. This functions similarly to the `:send_timeout` option provided by
    [`:gen_tcp`](`:gen_tcp`). Defaults to `true`.

  * `:tls` - A list of tls options as supported by [`:ssl`](`:ssl`). When using TLS it is highly recommended you
     set `:verify` to `:verify_peer`, select a CA trust store using the `:cacertfile` or `:cacerts` options.
     Additionally, further hardening can be achieved through other ssl options such as enabling
     certificate revocation via the `:crl_check` and `:crl_cache` options and customization of
     enabled protocols and cipher suites for your specific use-case. See [`:ssl`](`:ssl`) for details.

  """
  @spec start_link(
          address :: ip_address(),
          port :: :inet.port_number(),
          options :: ClientContract.options()
        ) :: {:ok, pid()}

  def start_link(address, port, options \\ []) do
    :gen_statem.start_link(
      __MODULE__,
      [address: normalize_address!(address), port: port] ++ options,
      []
    )
  end

  @doc """
  Returns true if the connection is open and established, otherwise false.
  """
  @spec is_connected?(pid :: pid()) :: boolean()
  def is_connected?(pid) when is_pid(pid), do: :gen_statem.call(pid, :is_connected)

  @doc """
  Instructs the client to disconnect (if connected) and attempt a reconnect.
  """
  @spec reconnect(pid :: pid()) :: :ok
  def reconnect(pid), do: :gen_statem.call(pid, :reconnect)

  @doc """
  Sends a message and receives a response.

  send/4 supports both `HL7.Message` and String.t().

  All messages and responses will be wrapped and unwrapped via `MLLP.Envelope.wrap_message/1` and
  `MLLP.Envelope.unwrap_message/1` respectively

  In case the payload provided is an `HL7.Message.t()` the acknowledgment returned from the server
  will always be verified via `MLLP.Ack.verify_ack_against_message/2`. This is the only case
  where an `MLLP.Ack.ack_verification_result()` will be returned.

  ## Options

  * `:reply_timeout` - Optionally specify a timeout value for receiving a response. Must be a positive integer or
     `:infinity`. Defaults to 60 seconds.
  """
  @impl true
  @spec send(
          pid :: pid,
          payload :: HL7.Message.t() | String.t() | binary(),
          options :: ClientContract.send_options(),
          timeout :: non_neg_integer() | :infinity
        ) ::
          {:ok, String.t()}
          | MLLP.Ack.ack_verification_result()
          | {:error, ClientContract.client_error()}

  def send(pid, payload, options \\ %{}, timeout \\ :infinity)

  def send(pid, %HL7.Message{} = payload, options, timeout) do
    raw_message = to_string(payload)

    case :gen_statem.call(pid, {:send, raw_message, options}, timeout) do
      {:ok, reply} ->
        verify_ack(reply, raw_message)

      err ->
        err
    end
  end

  def send(pid, payload, options, timeout) do
    case :gen_statem.call(pid, {:send, payload, options}, timeout) do
      {:ok, wrapped_message} ->
        {:ok, MLLP.Envelope.unwrap_message(wrapped_message)}

      err ->
        err
    end
  end

  @doc """
  Sends a message without awaiting a response.

  Given the synchronous nature of MLLP/HL7 this function is mainly useful for
  testing purposes.
  """
  @impl true
  def send_async(pid, payload, timeout \\ :infinity)

  def send_async(pid, %HL7.Message{} = payload, timeout) do
    send_async(pid, to_string(payload), timeout)
  end

  def send_async(pid, payload, timeout) when is_binary(payload) do
    :gen_statem.call(pid, {:send_async, payload, []}, timeout)
  end

  @doc """
  Stops an MLLP.Client given a MLLP.Client pid.

  This function will always return `:ok` per `:gen_statem.stop/1`, thus
  you may give it a pid that references a client which is already stopped.
  """
  @spec stop(pid :: pid()) :: :ok
  def stop(pid), do: :gen_statem.stop(pid)

  @header MLLP.Envelope.sb()
  @trailer MLLP.Envelope.eb_cr()

  ## :gen_statem callbacks
  @impl true
  def callback_mode() do
    [:state_functions, :state_enter]
  end

  @impl true
  @spec init(Keyword.t()) ::
          {:ok, :disconnected, MLLP.Client.t(), [{:next_event, :internal, :connect}]}
  def init(options) do
    opts =
      options
      |> Enum.into(%{tls: []})
      |> validate_options()
      |> maybe_set_default_options()
      |> put_socket_address()

    {:ok, :disconnected, struct(State, opts), [{:next_event, :internal, :connect}]}
  end

  ############################
  #### Disconnected state ####
  ############################

  def disconnected(:enter, :disconnected, state) do
    {:keep_state, state, reconnect_action(state)}
  end

  def disconnected(:enter, current_state, state) when current_state in [:connected, :receiving] do
    Logger.error("Connection closed")
    {:keep_state, state, reconnect_action(state)}
  end

  def disconnected(:internal, :connect, state) do
    {result, new_state} = attempt_connection(state)

    case result do
      :error ->
        {:keep_state, new_state, reconnect_action(new_state)}

      :ok ->
        {:next_state, :connected, new_state}
    end
  end

  def disconnected(:state_timeout, :reconnect, data) do
    actions = [{:next_event, :internal, :connect}]
    {:keep_state, data, actions}
  end

  def disconnected({:call, from}, :reconnect, _data) do
    Logger.debug("Request to reconnect accepted")
    {:keep_state_and_data, [{:reply, from, :ok}, {:next_event, :internal, :connect}]}
  end

  def disconnected({:call, from}, {:send, _message, _options}, state) do
    actions = [{:reply, from, {:error, new_error(:send, state.tcp_error)}}]
    {:keep_state_and_data, actions}
  end

  def disconnected({:call, from}, :is_connected, _state) do
    {:keep_state_and_data, [{:reply, from, false}]}
  end

  def disconnected(event, unknown, _state) do
    unexpected_message(:disconnected, event, unknown)
  end

  #########################
  #### Connected state ####
  #########################
  def connected(:enter, :disconnected, _state) do
    Logger.debug("Connection established")
    :keep_state_and_data
  end

  def connected(:enter, :receiving, _state) do
    :keep_state_and_data
  end

  def connected({:call, from}, {send_type, message, options}, state)
      when send_type in [:send, :send_async] do
    payload = MLLP.Envelope.wrap_message(message)

    case state.tcp.send(state.socket, payload) do
      :ok ->
        {:next_state, :receiving,
         state
         |> Map.put(:context, :recv)
         |> Map.put(:caller, from), send_action(send_type, from, options, state)}

      {:error, reason} ->
        telemetry(
          :status,
          %{
            status: :disconnected,
            error: format_error(reason),
            context: "send message failure"
          },
          state
        )

        error_reply = {:error, new_error(:send, reason)}
        {:keep_state_and_data, [{:reply, from, error_reply}]}
    end
  end

  def connected({:call, from}, :is_connected, _state) do
    {:keep_state_and_data, [{:reply, from, true}]}
  end

  def connected({:call, from}, :reconnect, _state) do
    {:keep_state_and_data, [{:reply, from, :ok}]}
  end

  def connected(:info, {transport, socket, _data} = msg, %{socket: socket} = state)
      when transport in [:tcp, :ssl] do
    receiving(:info, msg, state)
  end

  def connected(:info, {transport_closed, _socket}, state)
      when transport_closed in [:tcp_closed, :ssl_closed] do
    {:next_state, :disconnected, handle_closed(state)}
  end

  def connected(event, unknown, _state) do
    unexpected_message(:connected, event, unknown)
  end

  defp reconnect_action(
         %State{backoff: backoff, auto_reconnect_interval: auto_reconnect_interval} = _state
       ) do
    [{:state_timeout, reconnect_timeout(backoff, auto_reconnect_interval), :reconnect}]
  end

  defp send_action(:send, _from, options, state) do
    reply_timeout = Map.get(options, :reply_timeout, state.send_opts.reply_timeout)
    [{:state_timeout, reply_timeout, :receive_timeout}]
  end

  defp send_action(:send_async, from, _options, _state) do
    [{:reply, from, {:ok, :sent}}]
  end

  defp reconnect_timeout(nil, interval) do
    interval
  end

  defp reconnect_timeout(backoff, _interval) do
    backoff
    |> :backoff.get()
    |> :timer.seconds()
  end

  #########################
  #### Receiving state ####
  #########################
  def receiving(:enter, :connected, _state) do
    Logger.debug("Waiting for response...")
    :keep_state_and_data
  end

  def receiving({:call, from}, {:send, _message, _options}, _state) do
    {:keep_state_and_data, [{:reply, from, {:error, :busy_with_other_call}}]}
  end

  def receiving(:state_timeout, :receive_timeout, state) do
    {:next_state, :connected, reply_to_caller({:error, :timeout}, state)}
  end

  def receiving(:info, {transport, socket, data}, %{socket: socket} = state)
      when transport in [:tcp, :ssl] do
    new_data = handle_received(data, state)
    next_state = (new_data.caller && :receiving) || :connected
    {:next_state, next_state, new_data}
  end

  def receiving(:info, {transport_closed, socket}, %{socket: socket} = state)
      when transport_closed in [:tcp_closed, :ssl_closed] do
    {:next_state, :disconnected, handle_closed(state)}
  end

  def receiving(:info, {transport_error, socket, reason}, %{socket: socket} = state)
      when transport_error in [:tcp_error, :ssl_error] do
    {:next_state, :disconnected, handle_error(reason, maybe_close(reason, state))}
  end

  def receiving(event, unknown, _state) do
    unexpected_message(:receiving, event, unknown)
  end

  ########################################
  ### End of :gen_statem callbacks ###
  ########################################

  defp unexpected_message(state, event, message) do
    Logger.warn(
      "Event: #{inspect(event)} in state #{state}. Unknown message received => #{inspect(message)}"
    )

    :keep_state_and_data
  end

  ## Handle the (fragmented) responses to `send` request from a caller

  defp handle_received(_reply, %{caller: nil} = state) do
    ## No caller, ignore
    state
  end

  defp handle_received(reply, %{receive_buffer: buffer} = state) do
    new_buf = (buffer && buffer <> reply) || reply
    check = byte_size(new_buf) - 3

    case new_buf do
      <<@header, _ack::binary-size(check), @trailer>> ->
        ## The response is completed, send back to caller
        Logger.debug("Client #{inspect(self())} received a full MLLP!")
        reply_to_caller({:ok, new_buf}, state)

      <<@header, _rest::binary>> ->
        Logger.debug("Client #{inspect(self())} received a MLLP fragment: #{reply}")
        Map.put(state, :receive_buffer, new_buf)

      _ ->
        reply_to_caller({:error, :invalid_reply}, state)
    end
  end

  defp reply_to_caller(reply, %{caller: caller, context: context} = state) do
    caller && :gen_statem.reply(caller, format_reply(reply, context))
    reply_cleanup(state)
  end

  defp format_reply({:ok, result}, _context) do
    {:ok, result}
  end

  defp format_reply({:error, error}, context) do
    {:error, new_error(context, error)}
  end

  defp handle_closed(state) do
    handle_error(:closed, state)
  end

  ## Handle transport errors
  defp handle_error(reason, state) do
    Logger.error("Error: #{inspect(reason)}, state: #{inspect(state)}")

    reply_to_caller({:error, new_error(get_context(state), reason)}, state)
    |> stop_connection(reason, "closing connection to cleanup")
    |> tap(fn state ->
      telemetry(
        :status,
        %{status: :disconnected, error: format_error(reason)},
        state
      )
    end)
  end

  defp reply_cleanup(%State{} = state) do
    state
    |> Map.put(:caller, nil)
    |> Map.put(:receive_buffer, nil)
  end

  @doc false
  def terminate(reason = :normal, state) do
    Logger.debug("Client socket terminated. Reason: #{inspect(reason)} State #{inspect(state)}")
    stop_connection(state, reason, "process terminated")
  end

  def terminate(reason, state) do
    Logger.error("Client socket terminated. Reason: #{inspect(reason)} State #{inspect(state)}")
    stop_connection(state, reason, "process terminated")
  end

  defp maybe_close(reason, %{close_on_recv_error: true, context: context} = state) do
    stop_connection(state, reason, context)
  end

  defp maybe_close(_reason, state), do: state

  defp stop_connection(%State{} = state, error, context) do
    if state.socket != nil do
      telemetry(
        :status,
        %{status: :disconnected, error: format_error(error), context: context},
        state
      )

      state.tcp.close(state.socket)
    end

    state
    |> Map.put(:socket, nil)
    |> Map.put(:tcp_error, error)
  end

  defp backoff_succeed(%State{backoff: nil} = state), do: state

  defp backoff_succeed(%State{backoff: backoff} = state) do
    {_, new_backoff} = :backoff.succeed(backoff)
    %{state | backoff: new_backoff}
  end

  defp attempt_connection(%State{} = state) do
    telemetry(:status, %{status: :connecting}, state)
    opts = [:binary, {:packet, 0}, {:active, true}] ++ state.socket_opts ++ state.tls_opts

    case state.tcp.connect(state.address, state.port, opts, 2000) do
      {:ok, socket} ->
        state1 =
          state
          |> backoff_succeed()

        telemetry(:status, %{status: :connected}, state1)
        {:ok, %{state1 | socket: socket, tcp_error: nil}}

      {:error, reason} ->
        message = format_error(reason)
        Logger.error(fn -> "Error connecting to #{state.socket_address} => #{message}" end)

        telemetry(
          :status,
          %{status: :disconnected, error: format_error(reason), context: "connect failure"},
          state
        )

        {:error,
         state
         |> maybe_update_reconnection_timeout()
         |> Map.put(:tcp_error, reason)}
    end
  end

  defp maybe_update_reconnection_timeout(%State{backoff: nil} = state) do
    state
  end

  defp maybe_update_reconnection_timeout(%State{backoff: backoff} = state) do
    {_, new_backoff} = :backoff.fail(backoff)
    %{state | backoff: new_backoff}
  end

  defp telemetry(_event_name, _measurements, %State{telemetry_module: nil} = _metadata) do
    :ok
  end

  defp telemetry(event_name, measurements, %State{telemetry_module: telemetry_module} = metadata) do
    telemetry_module.execute([:client, event_name], add_timestamps(measurements), metadata)
  end

  defp add_timestamps(measurements) do
    measurements
    |> Map.put(:monotonic, :erlang.monotonic_time())
    |> Map.put(:utc_datetime, DateTime.utc_now())
  end

  defp validate_options(opts) do
    Map.get(opts, :address) || raise "No server address provided to connect to!"
    Map.get(opts, :port) || raise "No server port provdided to connect to!"
    opts
  end

  @default_opts %{
    telemetry_module: MLLP.DefaultTelemetry,
    tls_opts: [],
    socket_opts: [send_timeout: 60_000]
  }

  @default_send_opts %{
    reply_timeout: 60_000
  }

  defp maybe_set_default_options(opts) do
    socket_module = if opts.tls == [], do: TCP, else: TLS

    backoff =
      case opts[:use_backoff] do
        false ->
          nil

        _ ->
          backoff_seconds = opts[:backoff_max_seconds] || 180
          :backoff.init(1, backoff_seconds)
      end

    send_opts = Map.take(opts, Map.keys(@default_send_opts))

    send_opts = Map.merge(@default_send_opts, send_opts)

    socket_opts = Keyword.merge(@default_opts[:socket_opts], opts[:socket_opts] || [])

    opts
    |> Map.merge(@default_opts)
    |> Map.put_new(:tcp, socket_module)
    |> Map.put(:pid, self())
    |> Map.put(:tls_opts, opts.tls)
    |> Map.put(:send_opts, send_opts)
    |> Map.put(:socket_opts, socket_opts)
    |> Map.put(:backoff, backoff)
  end

  defp put_socket_address(%{address: address, port: port} = opts) do
    Map.put(opts, :socket_address, "#{format_address(address)}:#{port}")
  end

  defp format_address(address) when is_list(address) or is_atom(address) or is_binary(address) do
    to_string(address)
  end

  defp format_address(address), do: :inet.ntoa(address)

  defp verify_ack(raw_ack, raw_message) do
    ack = Envelope.unwrap_message(raw_ack)
    unwrapped_message = Envelope.unwrap_message(raw_message)
    Ack.verify_ack_against_message(unwrapped_message, ack)
  end

  defp new_error(context, %MLLP.Client.Error{} = error) do
    Map.put(error, :context, context)
  end

  defp new_error(context, error) do
    %MLLP.Client.Error{
      reason: error,
      context: context,
      message: format_error(error)
    }
  end

  defp get_context(%State{context: context}) do
    (context && context) || :unknown
  end

  defp normalize_address!({_, _, _, _} = addr), do: addr
  defp normalize_address!({_, _, _, _, _, _, _, _} = addr), do: addr

  defp normalize_address!(addr) when is_binary(addr) do
    String.to_charlist(addr)
  end

  defp normalize_address!(addr) when is_list(addr), do: addr

  defp normalize_address!(addr) when is_atom(addr), do: addr

  defp normalize_address!(addr),
    do: raise(ArgumentError, "Invalid server ip address : #{inspect(addr)}")
end
