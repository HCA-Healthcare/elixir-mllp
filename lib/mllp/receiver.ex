defmodule MLLP.Receiver do
  alias __MODULE__, as: State
  alias MLLP.{Ack, Envelope}

  use GenServer
  use Private
  require Logger

  defstruct socket: nil,
            transport: nil,
            buffer: "",
            dispatcher_module: MLLP.DefaultDispatcher,
            ack: true

  @behaviour :ranch_protocol
  @sb Envelope.sb()

  def start(port, dispatcher_module \\ MLLP.DefaultDispatcher, ack \\ true) do
    ref = make_ref()
    {:ok, pid} = :ranch.start_listener(ref, :ranch_tcp, [port: port], MLLP.Receiver, [dispatcher_module: dispatcher_module, ack: ack])
    {:ok, %{ref: ref, pid: pid, port: port}}
  end

  def stop(port) do
    ref = get_ref_by_port(port)
    :ranch.stop_listener(ref)
  end

  defp get_ref_by_port(port) do
    :ranch.info()
    |> Enum.filter(fn {_k, v} -> v[:port] == port end)
    |> Enum.map(fn {k, _v} -> k end)
    |> List.first()
  end

  @doc false
  def start_link(ref, socket, transport, opts) do
    dispatcher_module = opts |> Keyword.get(:dispatcher_module)
    ack = opts |> Keyword.get(:ack)

    # the proc_lib spawn is required because of the :gen_server.enter_loop below.
    {:ok, :proc_lib.spawn_link(Elixir.MLLP.Receiver, :init, [[ref, socket, transport, dispatcher_module, ack]])}
  end

  def init([ref, socket, transport, dispatcher_module, ack]) do
    Logger.debug(fn ->
      "MLLP.Receiver initializing.
      ref:[#{inspect(ref)}]
      socket:[#{inspect(socket)}]
      transport:[#{inspect(transport)}
      ack:[#{inspect(ack)}]
      dispatcher module:[#{inspect(dispatcher_module)}]."
    end)

    :ok = :ranch.accept_ack(ref)
    :ok = transport.setopts(socket, active: :once)

    state = %State{
      socket: socket,
      transport: transport,
      buffer: "",
      dispatcher_module: dispatcher_module,
      ack: ack
    }

    # http://erlang.org/doc/man/gen_server.html#enter_loop-3
    :gen_server.enter_loop(Elixir.MLLP.Receiver, [], state)
  end

  # -------------------
  # GenServer callbacks
  # -------------------

  def handle_info({:tcp, socket, data}, state) do
    Logger.debug(fn -> "Receiver received data: [#{inspect(data)}]." end)

    state.transport.setopts(socket, active: :once)

    socket_reply_fun = fn message ->
      Logger.debug("Sending ACK: #{message}")
      state.transport.send(socket, message)
    end

    new_state =
      state
      |> buffer_socket_data(data)
      |> process_messages(socket_reply_fun)

    {:noreply, new_state}
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

  defp buffer_socket_data(state, data) do
    Logger.debug("Receiver.process state:[#{inspect(state)}].")
    new_buffer = state.buffer <> data
    %State{state | buffer: new_buffer}
  end

  private do
    defp process_messages(%State{dispatcher_module: dispatcher_module, ack: ack} = state, socket_reply_fun) do
      {remnant_buffer, messages} = state.buffer |> extract_messages()

      messages
      |> Enum.each(&process_message(&1, socket_reply_fun, dispatcher_module, ack))

      %State{state | buffer: remnant_buffer}
    end

    defp process_message(
           <<"MSH", _::binary>> = message,
           socket_reply_fun,
           dispatcher_module,
           ack \\ true
         ) do
      result = apply(dispatcher_module, :dispatch, [message])
      if ack do
        Logger.info("prepare ack message")
        ack_message =
          result
          |> case do
            {:ok, :application_accept} ->
              Ack.get_ack_for_message(message, :application_accept)

            {:ok, :application_reject, message} ->
              Ack.get_ack_for_message(message, :application_reject, message)

            {:ok, :application_error, message} ->
              Ack.get_ack_for_message(message, :application_error, message)

            {:error, %{type: error_type, message: error_message}} ->
              Ack.get_ack_for_message(
                message,
                :application_error,
                "(#{inspect(error_type)})" <> error_message
              )
          end

        socket_reply_payload =
          ack_message
          |> Envelope.wrap_message()

        socket_reply_fun.(socket_reply_payload)
      end
    end

    defp process_message(
           _junk_message,
           socket_reply_fun,
           _dispatcher_module,
           _ack
         ) do
      ack_message = Ack.get_invalid_hl7_received_ack_message()

      socket_reply_payload =
        ack_message
        |> Envelope.wrap_message()

      socket_reply_fun.(socket_reply_payload)
    end

    defp extract_messages(buffer) when is_binary(buffer) do
      {remaining, messages} =
        buffer
        |> String.split(Envelope.eb_cr())
        |> extract_messages([])

      {remaining, messages |> Enum.reverse()}
    end

    defp extract_messages([last], acc) do
      {last, acc}
    end

    defp extract_messages([raw_message | tail], acc) do
      next_acc =
        case raw_message do
          <<@sb, message::binary>> ->
            [message | acc]

          <<"MSH", _::binary>> = message ->
            # Missing <SB>, but we can still deal with this
            Logger.warn(
              "MLLP Receiver received message data that did not begin with <SB>. Malformed data: #{
                message
              }"
            )

            [message | acc]

          bad_data ->
            Logger.error(
              "MLLP Receiver is discarding malformed message data because it did not begin with <SB> or `MSH`. Malformed data: #{
                bad_data
              }"
            )

            acc
        end

      extract_messages(tail, next_acc)
    end
  end
end
