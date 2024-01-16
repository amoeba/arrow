import os

import pyarrow as pa
import pyarrow.flight


def list_all_flights(client):
    print(f"[PID: {os.getpid()}]: list_all_flights() called")

    for fl in client.list_flights():
        print(
            f"[PID: {os.getpid()}]: got flightinfo for '{fl.descriptor.path[0].decode()}'"
        )


client = pa.flight.connect("grpc://0.0.0.0:8815")

parent_pid = os.getpid()
print(f"parent PID is {parent_pid}")

pid = os.fork()

list_all_flights(client)
