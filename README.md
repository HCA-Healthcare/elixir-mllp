# elixir-mllp

An Elixir library for transporting HL7 messages via MLLP (Minimal Lower Layer Protocol)

## Status

This project is not at v1.0 yet. The API and internals will likely change quite a bit between now and v1.0. Also, be aware of the details of the license (Apache 2.0).

## Usage

### HL7 over MLLP

First, let's start an MLLP.Receiver on port 4090.
```
{:ok, r4090} = MLLP.Receiver.start(4090)
```

Next, start an MLLP.Sender process and store its PID.
```
{:ok, s1} = MLLP.Sender.start_link({127,0,0,1}, 4090)
```

Alternatively, you could start a Sender using a DNS name rather than an IP address.
```
{:ok, s1} = MLLP.Sender.start_link("localhost", 4090)
```


Now send an HL7 message.
```
MLLP.Sender.send_hl7_and_receive_ack(s1, HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new())
```

You will see log info like...
```

15:56:07.217 [debug] Receiver received data: [<<11, 77, 83, 72, 124, 94, 126, 92, 38, 124, 77, 101, 103, 97, 82, 101, 103, 124, 88, 89, 90, 72, 111, 115, 112, 67, 124, 83, 117, 112, 101, 114, 79, 69, 124, 88, 89, 90, 73, 109, 103, 67, 116, 114, 124, 50, 48, 48, 54, 48, ...>>].
 
15:56:07.217 [error] MLLP.Dispatcher not set. The DefaultDispatcher simply logs and discards messages. Message type: mllp_hl7 Message: MSH|^~\&|MegaReg|XYZHospC|SuperOE|XYZImgCtr|20060529090131-0500||ADT^A01^ADT_A01|01052901|P|DG1|1||786.50^CHEST PAIN, UNSPECIFIED^I9|||A|||FFMD^0010^UAMC^L||67890^GRAINGER^LUCY^X^^^MD^0010^UAMC^L|MED|||||A0||13579^POTTER^SHERMAN^T^^^MD^0010^UAMC^L|||||||||||||||||||||||||||2006052909000^^O|||||||0105I30001^^^99DEF^AN
 
15:56:07.218 [debug] MLLP Envelope performed unnecessary unwrapping of unwrapped message
{:error, :application_reject,
 %MLLP.Ack{
   acknowledgement_code: "AR",
   hl7_ack_message: nil,
   text_message: "A real MLLP message dispatcher was not provided"
 }}
```

The Logger debug part tells us that the Receiver received the HL7 message. The Logger error part says we haven't set a Dispatcher and the message will not be routed anywhere other than to the console log. Finally, the return value (`{:error,  :application_reject, ...}`) is a NACK. The DefaultDispatcher will not reply with an `:application_accept`.

Now, we will stop the Receiver.

```
 MLLP.Receiver.stop(4090)
```

### Custom message dispatcher

Now we will set up a receiver with a custom dispatcher. 

```
defmodule DemoDispatcher do
  @behaviour MLLP.Dispatcher

  def dispatch(:mllp_hl7, message, state) when is_binary(message) do
    # Put your message handling logic here

    reply =
      MLLP.Ack.get_ack_for_message(
        message,
        :application_accept
      )
      |> to_string()
      |> MLLP.Envelope.wrap_message()

    {:ok, %{state | reply_buffer: reply}}
  end
end
```

Now we can configure a Receiver to use our newly defined DemoDispatcher.

```
{:ok, r4090} = MLLP.Receiver.start(4090, DemoDispatcher)
```

Next, let's set up a Sender to exercise our new Receiver.

```
{:ok, s2} = MLLP.Sender.start_link({127,0,0,1}, 4090)
```

Now when you send a message to the Receiver's port, the custom DemoDispatcher will be used. 

```
MLLP.Sender.send_hl7_and_receive_ack(s2, HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new())
```

Notice the DefaultDispatcher warning is no longer in the Logger output.

```
15:43:26.605 [debug] MLLP Envelope performed unnecessary unwrapping of unwrapped message
 
15:43:26.606 [debug] Receiver received data: [<<11, 77, 83, 72, 124, 94, 126, 92, 38, 124, 77, 101, 103, 97, 82, 101, 103, 124, 88, 89, 90, 72, 111, 115, 112, 67, 124, 83, 117, 112, 101, 114, 79, 69, 124, 88, 89, 90, 73, 109, 103, 67, 116, 114, 124, 50, 48, 48, 54, 48, ...>>].
{:ok, :application_accept,
 %MLLP.Ack{acknowledgement_code: "AA", hl7_ack_message: nil, text_message: ""}}

```


### Non-HL7 over MLLP

While the MLLP framing protocol is mostly for HL7, some companies also send and receive non-HL7 data over MLLP. If you find yourself needing to integrate with a system that has made this choice the following will be helpful.


```
defmodule ExpandedDemoDispatcher do
  @behaviour MLLP.Dispatcher

  def dispatch(:mllp_hl7, message, state) when is_binary(message) do
    # Your message handling logic here

    reply =
      MLLP.Ack.get_ack_for_message(message, :application_accept)
      |> to_string()
      |> MLLP.Envelope.wrap_message()
    
    {:ok, %{state | reply_buffer: reply}}
  end

  def dispatch(:mllp_unknown, message, state) when is_binary(message) do
    # Your message handling logic here

    reply = "Got the BLOB"

    {:ok, %{state | reply_buffer: reply}}
  end
end
```

Now, to use this expanded custom dispatcher with a Sender and Receiver.

Let's start by getting a new Receiver.

```
iex> {:ok, r4091} = MLLP.Receiver.start(4091, ExpandedDemoDispatcher)
{:ok,
 %{
   pid: #PID<0.367.0>,
   port: 4091,
   receiver_id: #Reference<0.144001725.3813670918.119240>
 }}
```

Next, start a Sender.
```
iex> {:ok, s3} = MLLP.Sender.start_link("localhost", 4091)
{:ok, #PID<0.383.0>}

```

Now let's send and receive non-HL7 data over MLLP
```
iex> MLLP.Sender.send_non_hl7_and_receive_reply(s3, "Hip hip hurray")
15:14:20.531 [debug] Receiver received data: [<<11, 72, 105, 112, 32, 104, 105, 112, 32, 104, 117, 114, 114, 97, 121, 28, 13>>].
{:ok, "Got the BLOB"}
```


## **Telemetry** (Sender only currently)

Can be namespaced or changed by passing a replacement for DefaultTelemetry.

The default emits `[:mllp, :sender, :status | :sending | :received]` telemetry events.
Emitted measurements contain status, errors, timestamps, etc.
The emitted metadata contains the Sender state.


## License

Elixir-MLLP source code is released under Apache 2 License. Check LICENSE file for more information.