# CertifiedRecords

The records of certified computations, shared by the experiment packages:

- `run_header(mod, script; params...)`: the header above a record, naming the script, the
  machine, the time, the commit of the package `mod` (and whether its tree was dirty), the
  Julia version, the threads and the parameters;
- `fmt_upper`: an upper bound printed so that the decimal written is at least the bound,
  for `Upper(x)`, IntervalArithmetic intervals and Arblib balls (package extensions);
- `write_endpoint`, `read_endpoint`: an interval endpoint written as the shortest decimal at
  its own precision, with the precision, so that it is read back exactly;
- `open_record`, `append_record`, `read_record`, `recorded_keys`: tab-separated records,
  read back by a driver to continue a run or to re-certify it row by row;
- `dataverse_files`, `dataverse_download`, `dataverse_add`: the files of a Dataverse dataset
  version, a download verified against the listed size and checksum, and a file added to a
  draft, verified against the size and checksum the installation reports (native API).

`dataverse_replace` is written but not exported until it has been run against an
installation.

    CERTIFIEDRECORDS_LIVE=1 julia --project=. -e 'using Pkg; Pkg.test()'

runs, besides the offline tests, read-only downloads from two published Harvard datasets;
with `CERTIFIEDRECORDS_LIVE_WRITE=1` and `CERTIFIEDRECORDS_SCRATCH_DOI=<a dataset whose draft
may be written to>` it also adds one small file to that draft, downloads it back and deletes
it, with the token in `default_token_file()`.
