module CertifiedRecords

# The records of certified computations: what a driver writes (a header naming the run,
# rows of upper bounds and exact interval endpoints), how it reads them back to continue
# or to re-certify a run, and how the records are deposited on and fetched from a
# Dataverse installation. Intervals of IntervalArithmetic and balls of Arblib are handled
# by the package extensions.

import HTTP
import JSON
import MD5
import SHA
import Printf

include("Records.jl")
include("Dataverse.jl")

end
