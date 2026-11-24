module CertifiedRecordsIntervalArithmeticExt

using CertifiedRecords
using IntervalArithmetic: Interval, sup, inf

"""
    fmt_upper(x::Interval)

The supremum of `x`, written as an upper bound by [`fmt_upper`](@ref).
"""
CertifiedRecords.fmt_upper(x::Interval) =
    CertifiedRecords._fmt_upper_big(CertifiedRecords._big_exact(sup(x)))


"""
    upper_bound(x::Interval, T = Float64)

The supremum of `x`, rounded up to `T`.
"""
CertifiedRecords.upper_bound(x::Interval, ::Type{T} = Float64) where {T<:AbstractFloat} = T(sup(x), RoundUp)

"""
    write_interval(x::Interval)

The infimum and the supremum of `x`.
"""
CertifiedRecords.write_interval(x::Interval) = CertifiedRecords.write_interval(inf(x), sup(x))

end
