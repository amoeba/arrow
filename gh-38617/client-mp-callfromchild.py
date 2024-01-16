import multiprocessing
import os

import pyarrow as pa
import pyarrow.flight as flight


# Flight objects aren't pickleable
#   https://github.com/apache/arrow/issues/35150
# so we share our client by global
client = flight.FlightClient("grpc://localhost:8815")


def list_all_flights(i):
    print(f"[PID: {os.getpid()}]: list_all_flights() called")

    for fl in client.list_flights():
        print(f"[PID: {os.getpid()}]: got flight '{fl.descriptor.path[0].decode()}'")


# Spin up a multiprocessing.Pool using fork
if __name__ == "__main__":
    # We actually want to catch non-fork cases too but we set fork here just for
    # testing
    multiprocessing.set_start_method("fork")

    print(f"Parent PID is {os.getpid()}")

    with multiprocessing.Pool(2) as p:
        p.map(list_all_flights, range(2))
