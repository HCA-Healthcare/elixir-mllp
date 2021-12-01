defmodule MLLP.Receiver do
  @moduledoc """
  A simple MLLP server.
  Minimal Lower Layer Protocol (MLLP) is an application level protocol which merely defines header and
  trailer delimiters for HL7 messages utilized in the healthcare industry for data interchange.
  ## Options
  The following options are required for starting an MLLP receiver either via `start/1` or indirectly via
  `child_spec/1` :
    - `:port` - The tcp port the receiver will listen on.
    - `:dispatcher` - Callback module messages ingested by the receiver will be passed to. This library ships with an
    echo only example dispatch module, `MLLP.EchoDispatcher` for example purposes, which can be provided as a value
    for this parameter.
  Optional parameters:
    - `:packet_framer` - Callback module for received packets. Defaults to `MLLP.DefaultPacketFramer`
    - `:transport_opts` - A map of parameters given to ranch as transport options. See
    [Ranch Documentation](https://ninenines.eu/docs/en/ranch/1.7/manual/) for all transport options that can be
    provided. The default `transport_opts` are `%{num_acceptors: 100, max_connections: 20_000}` if none are provided.
  """

  use GenServer

  require Logger

  alias MLLP.FramingContext

  @type dispatcher :: any()

  @type t() :: %MLLP.Receiver{
          socket: any(),
          transport: any(),
          buffer: String.t(),
          dispatcher_module: dispatcher()
        }

  @type options() :: [
          port: pos_integer(),
          dispatcher: module(),
          packet_framer: module(),
          transport_opts: :ranch.opts()
        ]

  @behaviour :ranch_protocol

  defstruct socket: nil,
            transport: nil,
            buffer: "",
            dispatcher_module: nil

  @doc """
  Starts an MLLP.Receiver.
      {:ok, info_map} = MLLP.Receiver.start(port: 4090, dispatcher: MLLP.EchoDispatcher)
  If successful it will return a map containing the pid of the listener, the port it's listening on, and the
  receiver_id (ref) created, otherwise an error tuple.
  Note that this function is in constrast with `child_spec/1` which can be used to embed MLLP.Receiver in your
  application or within a supervision tree as part of your application.
  This function is useful for starting an MLLP.Receiver from within a GenServer or for development and testing
  purposes.
  See [Options](#module-options) for details on required and optiomal parameters.
  """

  @spec start(options()) :: {:ok, map()} | {:error, any()}

  def start(opts \\ []) do
    args = to_args(opts)

    result =
      :ranch.start_listener(
        args.receiver_id,
        args.transport_mod,
        args.transport_opts,
        args.proto_mod,
        args.proto_opts
      )

    case result do
      {:ok, pid} ->
        {:ok, %{receiver_id: args.receiver_id, pid: pid, port: args.port}}

      {:error, :eaddrinuse} ->
        {:error, :eaddrinuse}
    end
  end

  @spec stop(any) :: :ok | {:error, :not_found}
  def stop(port) do
    receiver_id = get_receiver_id_by_port(port)
    :ok = :ranch.stop_listener(receiver_id)
  end

  @doc """
  A function which can be used to embed an MLLP.Receiver under Elixir v1.5+ supervisors.
  Unlike `start/1`, `start/2`, or `start/3` this function takes two additional options : `ref` and `transport_opts`.
  Note that if a `ref` option is not supplied a reference will be created for you using `make_ref/0`.
      children = [{MLLP.Receiver, [
          ref: MyRef,
          port: 4090,
          dispatcher: MLLP.EchoDispatcher,
          packet_framer: MLLP.DefaultPacketFramer,
          transport_opts: %{num_acceptors: 25, max_connections: 20_000}
        ]}
      ]
      Supervisor.init(children, strategy: :one_for_one)
  See [Options](#module-options) for details on required and optiomal parameters.
  ## Examples
      iex(1)> opts = [ref: MyRef, port: 4090, dispatcher: MLLP.EchoDispatcher, packet_framer: MLLP.DefaultPacketFramer]
      [
        ref: MyRef,
        port: 4090,
        dispatcher: MLLP.EchoDispatcher,
        packet_framer: MLLP.DefaultPacketFramer
      ]
      iex(2)> MLLP.Receiver.child_spec(opts)
      %{
        id: {:ranch_embedded_sup, MyRef},
        start: {:ranch_embedded_sup, :start_link,
         [
          MyRef,
          :ranch_tcp,
          %{socket_opts: [port: 4090], num_acceptors: 100, max_connections: 20_000},
          MLLP.Receiver,
          [packet_framer_module: MLLP.DefaultPacketFramer, dispatcher_module: MLLP.EchoDispatcher]
        ]},
        type: :supervisor
      }
  """
  @spec child_spec(options()) :: Supervisor.child_spec()
  def child_spec(opts) do
    args = to_args(opts)

    :ranch.child_spec(
      args.receiver_id,
      args.transport_mod,
      args.transport_opts,
      args.proto_mod,
      args.proto_opts
    )
  end

  @doc false
  def start_link(receiver_id, transport, options) do
    # the proc_lib spawn is required because of the :gen_server.enter_loop below.
    {:ok,
     :proc_lib.spawn_link(__MODULE__, :init, [
       [
         receiver_id,
         transport,
         options
       ]
     ])}
  end

  defp to_args(opts) do
    port =
      Keyword.get(opts, :port, nil) ||
        raise(ArgumentError, "No tcp port provided")

    dispatcher_mod =
      Keyword.get(opts, :dispatcher, nil) ||
        raise(ArgumentError, "No dispatcher module provided")

    Code.ensure_loaded?(dispatcher_mod) ||
      raise "The dispatcher module #{dispatcher_mod} could not be found."

    implements_behaviour?(dispatcher_mod, MLLP.Dispatcher) ||
      raise "The dispatcher module #{dispatcher_mod} does not implement the MLLP.Dispatcher behaviour"

    packet_framer_mod = Keyword.get(opts, :packet_framer, MLLP.DefaultPacketFramer)

    Code.ensure_loaded?(packet_framer_mod) ||
      raise "The packet framer module #{packet_framer_mod} could not be found."

    implements_behaviour?(packet_framer_mod, MLLP.PacketFramer) ||
      raise "The packet framer module #{packet_framer_mod} does not implement the MLLP.Dispatcher behaviour"

    receiver_id = Keyword.get(opts, :ref, make_ref())

    {transport_mod, transport_opts} =
      default_transport_opts()
      |> Map.merge(Keyword.get(opts, :transport_opts, %{}))
      |> update_transport_options(port)

    proto_mod = __MODULE__
    proto_opts = [packet_framer_module: packet_framer_mod, dispatcher_module: dispatcher_mod]

    %{
      receiver_id: receiver_id,
      port: port,
      transport_mod: transport_mod,
      transport_opts: transport_opts,
      proto_mod: proto_mod,
      proto_opts: proto_opts
    }
  end

  defp default_transport_opts() do
    %{num_acceptors: 100, max_connections: 20_000}
  end

  defp update_transport_options(transport_opts, port) do
    {transport_module, tls_options1, transport_opts1} =
      case Map.pop(transport_opts, :tls) do
        {nil, options1} ->
          Logger.warn(
            "Starting listener on a non secured socket, data will be passed over unencrypted connection!"
          )

          {:ranch_tcp, [], options1}

        {tls_options, options1} ->
          {:ranch_ssl, Keyword.merge(default_tls_options(), tls_options), options1}
      end

    socket_opts = get_socket_options(transport_opts, port) ++ tls_options1

    transport_opts2 = Map.put(transport_opts1, :socket_opts, socket_opts)

    {transport_module, transport_opts2}
  end

  defp get_socket_options(transport_opts, port) do
    transport_opts
    |> Map.get(:socket_opts, [])
    |> Keyword.put(:port, port)
  end

  defp default_tls_options() do
    [verify: :verify_peer]
  end

  defp get_receiver_id_by_port(port) do
    :ranch.info()
    |> Enum.filter(fn {_k, v} -> v[:port] == port end)
    |> Enum.map(fn {k, _v} -> k end)
    |> List.first()
  end

  # ===================
  # GenServer callbacks
  # ===================

  @doc false
  @spec init(Keyword.t()) ::
          {:ok, state :: any()}
          | {:ok, state :: any(), timeout() | :hibernate | {:continue, term()}}
          | :ignore
          | {:stop, reason :: any()}
  def init([receiver_id, transport, options]) do
    {:ok, socket} = :ranch.handshake(receiver_id, [])

    {:ok, server_info} = transport.sockname(socket)
    {:ok, client_info} = transport.peername(socket)

    :ok = transport.setopts(socket, active: :once)

    state = %{
      socket: socket,
      server_info: server_info,
      client_info: client_info,
      transport: transport,
      framing_context: %FramingContext{
        packet_framer_module: Keyword.get(options, :packet_framer_module),
        dispatcher_module: Keyword.get(options, :dispatcher_module)
      }
    }

    # http://erlang.org/doc/man/gen_server.html#enter_loop-3
    :gen_server.enter_loop(__MODULE__, [], state)
  end

  def handle_info({message, socket, data}, state) when message in [:tcp, :ssl] do
    Logger.debug(fn -> "Receiver received data: [#{inspect(data)}]." end)
    framing_context = handle_received_data(socket, data, state.framing_context, state.transport)
    {:noreply, %{state | framing_context: framing_context}}
  end

  def handle_info({message, _socket}, state) when message in [:tcp_closed, :ssl_closed] do
    Logger.debug("MLLP.Receiver tcp_closed.")
    {:stop, :normal, state}
  end

  def handle_info({message, _, reason}, state) when message in [:tcp_error, :tls_error] do
    Logger.error(fn -> "MLLP.Receiver encountered a tcp_error: [#{inspect(reason)}]" end)
    {:stop, reason, state}
  end

  def handle_info(:timeout, state) do
    Logger.debug("Receiver timed out.")
    {:stop, :normal, state}
  end

  def handle_info(msg, state) do
    Logger.warn("Unexpected handle_info for msg [#{inspect(msg)}].")
    {:noreply, state}
  end

  defp implements_behaviour?(mod, behaviour) do
    behaviours_found = Keyword.get(mod.__info__(:attributes), :behaviour, [])
    behaviour in behaviours_found
  end

  defp handle_received_data(socket, data, framing_context, transport) do
    transport.setopts(socket, active: :once)

    framing_context = framing_context
    framer = framing_context.packet_framer_module

    {:ok, framing_context2} = framer.handle_packet(data, framing_context)

    reply_buffer = framing_context2.reply_buffer

    if reply_buffer != "" do
      transport.send(socket, reply_buffer)
      %{framing_context2 | reply_buffer: ""}
    else
      framing_context2
    end
  end
end
