defmodule MLLP.Receiver do
  use GenServer

  require Logger

  alias MLLP.FramingContext

  @type dispatcher :: any()

  @type t :: %MLLP.Receiver{
          socket: any(),
          transport: any(),
          buffer: String.t(),
          dispatcher_module: dispatcher()
        }

  @behaviour :ranch_protocol

  defstruct socket: nil,
            transport: nil,
            buffer: "",
            dispatcher_module: MLLP.DefaultDispatcher

  @spec start(
          port :: non_neg_integer(),
          dispatcher_module :: module(),
          packet_framer_module :: module()
        ) :: {:ok, map()} | {:error, any()}

  def start(
        port,
        dispatcher_module \\ MLLP.DefaultDispatcher,
        packet_framer_module \\ MLLP.DefaultPacketFramer
      )
      when is_atom(packet_framer_module) and is_atom(dispatcher_module) do
    receiver_id = make_ref()

    transport_module = :ranch_tcp
    transport_options = [port: port]
    protocol_module = __MODULE__

    options = [packet_framer_module: packet_framer_module, dispatcher_module: dispatcher_module]

    result =
      :ranch.start_listener(
        receiver_id,
        transport_module,
        transport_options,
        protocol_module,
        options
      )

    case result do
      {:ok, pid} ->
        {:ok, %{receiver_id: receiver_id, pid: pid, port: port}}

      {:error, :eaddrinuse} ->
        {:error, :eaddrinuse}
    end
  end

  def stop(port) do
    receiver_id = get_receiver_id_by_port(port)

    :ok = :ranch.stop_listener(receiver_id)
  end

  @doc false
  def start_link(receiver_id, _, transport, options) do
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

  defp get_receiver_id_by_port(port) do
    :ranch.info()
    |> Enum.filter(fn {_k, v} -> v[:port] == port end)
    |> Enum.map(fn {k, _v} -> k end)
    |> List.first()
  end

  # ===================
  # GenServer callbacks
  # ===================

  @spec init(Keyword.t()) ::
          {:ok, state :: any()}
          | {:ok, state :: any(), timeout() | :hibernate | {:continue, term()}}
          | :ignore
          | {:stop, reason :: any()}
  def init([receiver_id, transport, options]) do
    {:ok, socket} = :ranch.handshake(receiver_id, [])

    {:ok, server_info} = :inet.sockname(socket)
    {:ok, client_info} = :inet.peername(socket)

    :ok = transport.setopts(socket, active: :once)

    state = %{
      socket: socket,
      server_info: server_info,
      client_info: client_info,
      transport: transport,
      framing_context: %FramingContext{
        packet_framer_module:
          Keyword.get(options, :packet_framer_module, MLLP.DefaultPacketFramer),
        dispatcher_module: Keyword.get(options, :dispatcher_module, MLLP.DefaultDispatcher)
      }
    }

    # http://erlang.org/doc/man/gen_server.html#enter_loop-3
    :gen_server.enter_loop(__MODULE__, [], state)
  end

  def handle_info({:tcp, socket, data}, state) do
    Logger.debug(fn -> "Receiver received data: [#{inspect(data)}]." end)

    state.transport.setopts(socket, active: :once)

    framing_context = state.framing_context
    framer = framing_context.packet_framer_module

    {:ok, framing_context2} = framer.handle_packet(data, framing_context)

    reply_buffer = framing_context2.reply_buffer

    framing_context3 =
      if reply_buffer != "" do
        state.transport.send(socket, reply_buffer)
        %{framing_context2 | reply_buffer: ""}
      else
        framing_context2
      end

    {:noreply, %{state | framing_context: framing_context3}}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.debug("MLLP.Receiver tcp_closed.")
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, _, reason}, state) do
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
end
