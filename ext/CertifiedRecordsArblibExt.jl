module CertifiedRecordsArblibExt

using CertifiedRecords
using Arblib: Arb, getinterval

"""
    fmt_upper(x::Arb)

The upper end of the interval enclosing the ball `x` (`Arblib.getinterval`, rounded
outward at the precision of `x`), written as an upper bound by [`fmt_upper`](@ref).
"""
CertifiedRecords.fmt_upper(x::Arb) =
    CertifiedRecords._fmt_upper_big(getinterval(BigFloat, x)[2])

end
