import pandas as pd
import pyarrow as pa
import pyarrow.flight


class FlightServer(pa.flight.FlightServerBase):
    def __init__(self, location="grpc://0.0.0.0:8815", **kwargs):
        super(FlightServer, self).__init__(location, **kwargs)
        self._location = location
        self._setup_datasets()

    def _setup_datasets(self):
        """
        Create a simple in-memory Arrow Table to make this example more
        self-contained
        """

        test_df = pd.DataFrame(
            {
                "x": range(5),
                "y": range(5),
                "z": range(5),
            }
        )

        self.datasets = [pa.Table.from_pandas(test_df)]

    def _make_flight_info(self, dataset):
        name = "fork_test_tbl"
        schema = dataset.schema
        descriptor = pa.flight.FlightDescriptor.for_path(name)
        endpoints = [pa.flight.FlightEndpoint(name, [self._location])]
        num_rows = dataset.num_rows

        return pa.flight.FlightInfo(schema, descriptor, endpoints, num_rows, -1)

    def list_flights(self, context, criteria):
        print("[SERVER] received list_flights from client")

        for dataset in self.datasets:
            yield self._make_flight_info(dataset)


if __name__ == "__main__":
    server = FlightServer()
    print("[SERVER] Starting FlightServer")
    server.serve()
