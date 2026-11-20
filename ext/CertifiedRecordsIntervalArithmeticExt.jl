module CertifiedRecordsIntervalArithmeticExt

using CertifiedRecords
using IntervalArithmetic: Interval, sup

"""
    fmt_upper(x::Interval)

The supremum of `x`, written as an upper bound by [`fmt_upper`](@ref).
"""
CertifiedRecords.fmt_upper(x::Interval) =
    CertifiedRecords._fmt_upper_big(CertifiedRecords._big_exact(sup(x)))

end
