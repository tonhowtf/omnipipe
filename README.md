# Omnipipe

TCP relay server that pairs two connections by a room code and pipes raw bytes between them. Designed as the transport layer for **OmniGet** peer-to-peer file transfers.

## How it works

```
Sender ──SEND <code>──▶ ┌──────────┐ ◀──RECV <code>── Receiver
                        │ Omnipipe  │
Sender ◀── READY ────── │  (relay)  │ ── READY ──▶ Receiver
                        └──────────┘
          raw bytes flow both ways after pairing
```

1. **Sender** connects via TCP and sends `SEND <code>\n`. The server creates a room and replies `WAIT\n`.
2. **Receiver** connects and sends `RECV <code>\n`. The server pairs both sockets and sends `READY\n` to each side.
3. From that point on, raw bytes are relayed bidirectionally until either side closes the connection.

Rooms expire automatically after 10 minutes if no receiver joins.

## Protocol

| Message            | Direction       | Description                        |
| ------------------ | --------------- | ---------------------------------- |
| `SEND <code>\n`    | client → server | Create a room and wait for a peer  |
| `RECV <code>\n`    | client → server | Join an existing room              |
| `WAIT\n`           | server → client | Room created, waiting for peer     |
| `READY\n`          | server → client | Peer connected, relay active       |
| `ERROR <reason>\n` | server → client | Something went wrong               |

## Configuration

| Variable | Default | Description       |
| -------- | ------- | ----------------- |
| `PORT`   | `9009`  | TCP listen port   |

## Requirements

- [Elixir](https://elixir-lang.org/install.html) ≥ 1.14

## Running

```bash
elixir omnipipe.exs
```

With a custom port:

```bash
PORT=4000 elixir omnipipe.exs
```

## Testing manually

In one terminal (sender):

```bash
echo -e "SEND myroom" | nc localhost 9009
```

In another terminal (receiver):

```bash
echo -e "RECV myroom" | nc localhost 9009
```

Both sides will receive `READY` and any subsequent data sent by one will appear on the other.

## License

Part of the OmniGet project.
