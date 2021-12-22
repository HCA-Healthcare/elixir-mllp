# mllp

An Elixir library for transporting HL7 messages via MLLP (Minimal Lower Layer Protocol)

## Status

This project is not at v1.0 yet. The API and internals will likely change quite a bit between now and v1.0. Also, be aware of the details of the license (Apache 2.0).

## Usage

### HL7 over MLLP

First, let's start an MLLP.Receiver on port 4090.
```
{:ok, r4090} = MLLP.Receiver.start(port: 4090, dispatcher: MLLP.EchoDispatcher)
```

Next, start an MLLP.Client process and store its PID.
```
{:ok, s1} = MLLP.Client.start_link({127,0,0,1}, 4090)
```

Alternatively, you could start a Client using a DNS name rather than an IP address.
```
{:ok, s1} = MLLP.Client.start_link("localhost", 4090)
```


Now send an HL7 message.
```
MLLP.Client.send(s1, HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new())
```

You will see log info like...
```

15:56:07.217 [debug] Receiver received data: [<<11, 77, 83, 72, 124, 94, 126, 92, 38, 124, 77, 101, 103, 97, 82, 101, 103, 124, 88, 89, 90, 72, 111, 115, 112, 67, 124, 83, 117, 112, 101, 114, 79, 69, 124, 88, 89, 90, 73, 109, 103, 67, 116, 114, 124, 50, 48, 48, 54, 48, ...>>].
 
15:56:07.217 [info] The EchoDispatcher simply logs and discards messages. Message type: mllp_hl7 Message: MSH|^~\&|MegaReg|XYZHospC|SuperOE|XYZImgCtr|20060529090131-0500||ADT^A01^ADT_A01|01052901|P|DG1|1||786.50^CHEST PAIN, UNSPECIFIED^I9|||A|||FFMD^0010^UAMC^L||67890^GRAINGER^LUCY^X^^^MD^0010^UAMC^L|MED|||||A0||13579^POTTER^SHERMAN^T^^^MD^0010^UAMC^L|||||||||||||||||||||||||||2006052909000^^O|||||||0105I30001^^^99DEF^AN
 
15:56:07.218 [debug] MLLP Envelope performed unnecessary unwrapping of unwrapped message
{:error, :application_reject,
 %MLLP.Ack{
   acknowledgement_code: "AR",
   hl7_ack_message: nil,
   text_message: "A real MLLP message dispatcher was not provided"
 }}
```

The Logger `[debug]` part tells us that the Receiver received the HL7 message. The Logger `[info]` part explains that the EchoDispatcher does not route the message anywhere (just "logs and discards" messages). Finally, the return value (`{:error,  :application_reject, ...}`) is a NACK. The EchoDispatcher will not reply with an `:application_accept`.

Now, we will stop the Receiver.

```
 MLLP.Receiver.stop(4090)
```

### Writing a message dispatcher

MLLP does not ship with a default message dispatcher as the cases can vary significantly from domain to domain. Instead,
MLLP provides you with helper libraries (e.g., [HL7](https://hex.pm/packages/elixir_hl7) and helper functions so you can
easily craft your own message dispatcher to suit your needs.

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
{:ok, r4090} = MLLP.Receiver.start(port: 4090, dispatcher: DemoDispatcher)
```

Next, let's set up a Client to exercise our new Receiver.

```
{:ok, s2} = MLLP.Client.start_link({127,0,0,1}, 4090)
```

Now when you send a message to the Receiver's port, the custom DemoDispatcher will be used. 

```
MLLP.Client.send(s2, HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new())
```

Notice the DemoDispatcher warning is no longer in the Logger output.

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

Now, to use this expanded custom dispatcher with a Client and Receiver.

Let's start by getting a new Receiver.

```
iex> {:ok, r4091} = MLLP.Receiver.start(port: 4091, dispatcher: ExpandedDemoDispatcher)
{:ok,
 %{
   pid: #PID<0.367.0>,
   port: 4091,
   receiver_id: #Reference<0.144001725.3813670918.119240>
 }}
```

Next, start a Client.
```
iex> {:ok, s3} = MLLP.Client.start_link("localhost", 4091)
{:ok, #PID<0.383.0>}

```

Now let's send and receive non-HL7 data over MLLP
```
iex> MLLP.Client.send(s3, "Hip hip hurray")
15:14:20.531 [debug] Receiver received data: [<<11, 72, 105, 112, 32, 104, 105, 112, 32, 104, 117, 114, 114, 97, 121, 28, 13>>].
{:ok, "Got the BLOB"}
```


## **Telemetry** (Client only currently)

Can be namespaced or changed by passing a replacement for DefaultTelemetry.

The default emits `[:mllp, :client, :status | :sending | :received]` telemetry events.
Emitted measurements contain status, errors, timestamps, etc.
The emitted metadata contains the Client state.

## Using TLS
Support for TLS can be added for MLLP protocol to secure the data transfer between a client and receiver. Follow steps below to start a receiver and client using TLS
#### Create certificates
The first step in TLS configuration is to create a TLS certificates, which can be used by the server to start the listener. To help you with creating self signed certificate, run following script:

`sh tls/tls.sh`

This script creates the following certs:
- root ca
- server certificate signed by root ca
- client certificate signed by root ca
- expired client certificate signed by root ca
### Start Receiver

```
iex> MLLP.Receiver.start(port: 8154, dispatcher: MLLP.EchoDispatcher, transport_opts: %{tls: [cacertfile: "tls/root-ca/ca_certificate.pem", verify: :verify_none, certfile: "tls/server/server_certificate.pem", keyfile: "tls/server/private_key.pem"]})
```

### Start Client
```
iex> {:ok, s3} = MLLP.Client.start_link("localhost", 8154, tls: [verify: :verify_peer, cacertfile: "tls/root-ca/ca_certificate.pem"])
```

### Send a message
```
iex> MLLP.Client.send(s3, HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new())
```

## Using Client Certificates
MLLP listener can enforce client to provide a valid certificate before establishing a successful connection. Follow steps below to use client cert with a listener

### Start MLLP listener with :verify_peer option
```
iex> MLLP.Receiver.start(port: 8154, dispatcher: MLLP.EchoDispatcher, transport_opts: %{tls: [cacertfile: "tls/root-ca/ca_certificate.pem", verify: :verify_peer, certfile: "tls/server/server_certificate.pem", keyfile: "tls/server/private_key.pem"]})
```

### Start MLLP Client with client cert
```
iex> {:ok, s3} = MLLP.Client.start_link("localhost", 8154, tls: [verify: :verify_peer, cacertfile: "tls/root-ca/ca_certificate.pem", certfile: "tls/client/client_certificate.pem", keyfile: "tls/client/private_key.pem"])
```

### Send a message
```
iex> MLLP.Client.send(s3, HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new())
```

## Using Client Restrictions
MLLP listener supports two options to restrict incoming client connections to make sure it accepts only trusted clients.

1) IP/DNS restriction - In this mode, we can restrict incoming connections using Client IP/DNS.
2) Client Cert Check - If `verify: :verify_peer` option is enabled on listener, it will enforce client to send a valid client cert and will only allow the connection if certificate returned from the client is valid and trusted.

Here are couple of exmaples of using client restrictions
### Options 1 - Client IP/DNS restrictions
#### Start MLLP listener with allowed_clients options
```
iex> MLLP.Receiver.start(port: 8154, dispatcher: MLLP.EchoDispatcher, allowed_clients: ["localhost"])
```
### Start MLLP Client
```
iex> {:ok, s3} = MLLP.Client.start_link("localhost", 8154)
```
### Send a message
```
iex> MLLP.Client.send(s3, HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new())
```

***In this example starting a client on another server other than localhost will fail and a warning will be logged on the server***

`[warn]  Failed to verify client {ip, port}, error: :client_ip_not_allowed`

***This example provided is without TLS, We can modify it to use with TLS. Make sure to specify `verify: :verify_none` option in transport_opts on the listener. See [Using TLS](#using-tls): for details on setting up TLS connections.***

### Options 2 - Client Cert Check
#### Start MLLP listener with TLS and allowed_clients options
```
iex> MLLP.Receiver.start(port: 8154, dispatcher: MLLP.EchoDispatcher, allowed_clients: ["client-1"], transport_opts: %{tls: [cacertfile: "tls/root-ca/ca_certificate.pem", verify: :verify_peer, certfile: "tls/server/server_certificate.pem", keyfile: "tls/server/private_key.pem"]})
```
### Start MLLP Client
```
iex> {:ok, s3} = MLLP.Client.start_link("localhost", 8154, tls: [verify: :verify_peer, cacertfile: "tls/root-ca/ca_certificate.pem", certfile: "tls/client/client_certificate.pem", keyfile: "tls/client/private_key.pem"])
```

### Send a message
```
iex> MLLP.Client.send(s3, HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new())
```
***In the above scenarios we start a client with a valid certificate, but the cert issued is not one of the trusted client by the listener, thus the connection fails and a warning is logged by the listener***

`[warn]  Failed to verify client {ip, port}, error: :fail_to_verify_client_cert`

## License

Elixir-MLLP source code is released under Apache 2 License. Check LICENSE file for more information.