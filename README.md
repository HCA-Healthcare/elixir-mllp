# elixir-mllp

An Elixir library for transporting HL7 messages via MLLP (Minimal Lower Layer Protocol)

## Status

This project is not at v1.0 yet; it is a v0.0.x work-in-progress. The API and internals will likely change quite a bit between now and v1.0. Also, be aware of the details of the license (Apache 2.0).

## Usage

Start an MLLP.Receiver on port 4090 
```
{:ok, r4090} = MLLP.Receiver.start(4090)
```

Start an MLLP.Sender process and store its PID
```
{:ok, s1} = MLLP.Sender.start_link({{127,0,0,1}, 4090})
```



Send a message
```

MLLP.Sender.send_message(s1, HL7.Examples.wikipedia_sample_hl7())
 MLLP.Receiver.stop(4090)

```

## License

Elixir-MLLP source code is released under Apache 2 License. Check LICENSE file for more information.