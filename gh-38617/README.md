# GH-38617

Reproductions for bug reported in <https://github.com/apache/arrow/issues/38617>.

## Requirements

- Recent Python (tested on 3.11, 3.12)
- `python -m pip install -r requirements.txt`
- Linux or Docker if not on a Linux

## Running

Each test uses the same FlightServer script, `server.py`.
Either run it in a separate shell or backgrounded:

```sh
python server.py &
```

### Tests

1. `client-osfork-callfromchild.py`: (`CallFromChild`) Test creating a FlightClient, forking, using the Client in the _child_ process.
2. `client-osfork-callfromparent.py`: (`CallFromParent`) Test creating a FlightClient, forking, using the Client in the _parent_ process.
3. `client-osfork-callfromboth.py`: (`CallFromBoth`) Test creating a FlightClient, forking, using the Client in the _both the parent and child processes_.
4. `client-mp-callfromchild.py`: (`CallWithPool`) Test creating a global FlightClient in the parent and sharing it with `multiprocessing.Pool`.

### Docker

In case it's useful, there's a Dockerfile in this folder to help test.
Build and start a shell in the container:

```sh
docker build . -t fork
docker run -it fork /bin/bash
```

Then run the server (backgrounded) and then the client:

```sh
python server.py &
python {client-test-script}.py
```

## Results

1. `CallFromChild`: Breaks. The RPC doesn't appear to ever run, server handler never invoked.
2. `CallFromParent`: Works fine. The RPC runs as expected.
3. `CallFromBoth`: Breaks. Either segfaults, only the parent RPC runs, or a long stall followed by a GRPC error. See Details.
4. `CallWithPool`: Breaks. Hangs indefinitely before any child RPC starts.

## Details

With the test `CallFromBoth, we can sometimes get a strange GRPC error:

```sh
$ python client-osfork-callfromboth.py
[PID: 126]: before fork
[PID: 136]: safe() called
[PID: 136]: unsafe() called
[PID: 126]: safe() called
[PID: 126]: unsafe() called
<<< TERMINAL HANGS >>>
Traceback (most recent call last):
  File "/work/client.py", line 50, in <module>
    unsafe(client)
  File "/work/client.py", line 32, in unsafe
    for fl in client.list_flights():
  File "pyarrow/_flight.pyx", line 1577, in list_flights
  File "pyarrow/_flight.pyx", line 1581, in pyarrow._flight.FlightClient.list_flights
  File "pyarrow/_flight.pyx", line 68, in pyarrow._flight.check_flight_status
pyarrow._flight.FlightUnavailableError: Flight returned unavailable error, with message: failed to connect to all addresses; last error: UNKNOWN: ipv4:0.0.0.0:8815: connection attempt timed out before receiving SETTINGS fram
```
