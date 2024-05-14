.. Licensed to the Apache Software Foundation (ASF) under one
.. or more contributor license agreements.  See the NOTICE file
.. distributed with this work for additional information
.. regarding copyright ownership.  The ASF licenses this file
.. to you under the Apache License, Version 2.0 (the
.. "License"); you may not use this file except in compliance
.. with the License.  You may obtain a copy of the License at

..   http://www.apache.org/licenses/LICENSE-2.0

.. Unless required by applicable law or agreed to in writing,
.. software distributed under the License is distributed on an
.. "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
.. KIND, either express or implied.  See the License for the
.. specific language governing permissions and limitations
.. under the License.

Installing PyArrow
==================

System Compatibility
--------------------

PyArrow is regularly built and tested on Windows, macOS and various
Linux distributions. We strongly recommend using a 64-bit system.

Python Compatibility
--------------------

PyArrow is currently compatible with Python 3.8, 3.9, 3.10 and 3.11.

Using Conda
-----------

Install the latest version of PyArrow from
`conda-forge <https://conda-forge.org/>`_ using `Conda <https://conda.io>`_:

.. code-block:: bash

    conda install -c conda-forge pyarrow

.. note::

    While the ``pyarrow`` `conda-forge <https://conda-forge.org/>`_ package is
    the right choice for most users, both a minimal and maximal variant of the
    package exist, either of which may be better for your use case. See
    :ref:`python-conda-differences`.

Using Pip
---------

Install the latest version from `PyPI <https://pypi.org/>`_ (Windows, Linux,
and macOS):

.. code-block:: bash

    pip install pyarrow

If you encounter any importing issues of the pip wheels on Windows, you may
need to install the `Visual C++ Redistributable for Visual Studio 2015
<https://www.microsoft.com/en-us/download/details.aspx?id=48145>`_.

.. warning::
   On Linux, you will need pip >= 19.0 to detect the prebuilt binary packages.

Installing nightly packages or from source
------------------------------------------

See :ref:`python-development`.

Dependencies
------------

Required dependency

* **NumPy 1.16.6** or higher.

Optional dependencies

* **pandas 1.0** or higher,
* **cffi**.

Additional packages PyArrow is compatible with are :ref:`fsspec <filesystem-fsspec>`
and **pytz**, **dateutil** or **tzdata** package for timezones.

tzdata on Windows
^^^^^^^^^^^^^^^^^

While Arrow uses the OS-provided timezone database on Linux and macOS, it requires a
user-provided database on Windows. To download and extract the text version of
the IANA timezone database follow the instructions in the C++
:ref:`download-timezone-database` or use pyarrow utility function
`pyarrow.util.download_tzdata_on_windows()` that does the same.

By default, the timezone database will be detected at ``%USERPROFILE%\Downloads\tzdata``.
If the database has been downloaded in a different location, you will need to set
a custom path to the database from Python:

.. code-block:: python

   >>> import pyarrow as pa
   >>> pa.set_timezone_db_path("custom_path")


.. _python-conda-differences:

Differences between conda-forge packages
----------------------------------------

PyArrow is packaged on `conda-forge <https://conda-forge.org/>`_ as three
separate packages, each providing varying levels of functionality. This is in
contrast to PyPi, where only a single PyArrow package is provided.

The purpose of this split is to minimize the size of the installed package for
most users (``pyarrow``), provide a smaller, minimal package for specialized use
cases (``pyarrow-core``), while still providing a complete package for users who
require it (``pyarrow-all``).

The ``pyarrow-core`` package includes the following functionality:

- Data Types
- Compute Functions (i.e., ``pyarrow.compute``)
- Memory and I/O interfaces
- Streaming, Serialization, and IPC (i.e., ``pyarrow.ipc``)
- Filesystem Interfaces (HDFS, S3, GCS, etc.)
- File formats: Arrow/Feather, JSON, CSV, ORC (but not Parquet)

The table below lists the functionality provided by each package and may be
useful when deciding to use one package over another:

+------------+---------------------+--------------+---------+-------------+
| Component  | Package             | pyarrow-core | pyarrow | pyarrow-all |
+------------+---------------------+--------------+---------+-------------+
| Core       | pyarrow-core        | ✓            | ✓       | ✓           |
+------------+---------------------+--------------+---------+-------------+
| Parquet    | libparquet          |              | ✓       | ✓           |
+------------+---------------------+--------------+---------+-------------+
| Dataset    | libarrow-dataset    |              | ✓       | ✓           |
+------------+---------------------+--------------+---------+-------------+
| Acero      | libarrow-acero      |              | ✓       | ✓           |
+------------+---------------------+--------------+---------+-------------+
| Substrait  | libarrow-substrait  |              | ✓       | ✓           |
+------------+---------------------+--------------+---------+-------------+
| Flight     | libarrow-flight     |              |         | ✓           |
+------------+---------------------+--------------+---------+-------------+
| Flight SQL | libarrow-flight-sql |              |         | ✓           |
+------------+---------------------+--------------+---------+-------------+
| Gandiva    | libarrow-gandiva    |              |         | ✓           |
+------------+---------------------+--------------+---------+-------------+

Creating Custom Selections
^^^^^^^^^^^^^^^^^^^^^^^^^^

If you know which components you need and want to control what's installed, you
can create a custom selection of packages to include just the extra features you
need. For example, to install ``pyarrow-core`` and just support for reading and
writing Parquet, install ``libparquet`` alongside ``pyarrow-core``:

.. code-block:: shell

    conda install pyarrow-core libparquet

Or if you wish to use ``pyarrow`` but need support for Flight RPC:

.. code-block:: shell

    conda install pyarrow libarrow-flight
