import os

import pyarrow as pa
import pyarrow.flight


def list_all_flights(client):
    print(f"[PID: {os.getpid()}]: list_all_flights() called")

    for fl in client.list_flights():
        print(
            f"[PID: {os.getpid()}]: got flightinfo for '{fl.descriptor.path[0].decode()}'"
        )


# create a separate client for the parent to use
parent_client = pa.flight.connect("grpc://0.0.0.0:8815")

parent_pid = os.getpid()
print(f"parent PID is {parent_pid}")

pid = os.fork()

if os.getpid() != parent_pid:
    # create a new client for just the child to use
    child_client = pa.flight.connect("grpc://0.0.0.0:8815")
    list_all_flights(child_client)
else:
    list_all_flights(parent_client)
