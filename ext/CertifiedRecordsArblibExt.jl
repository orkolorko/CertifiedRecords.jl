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


"""
    upper_bound(x::Arb, T = Float64)

The upper end of the interval enclosing the ball `x`, rounded up to `T`.
"""
CertifiedRecords.upper_bound(x::Arb, ::Type{T} = Float64) where {T<:AbstractFloat} =
    T(getinterval(BigFloat, x)[2], RoundUp)

"""
    write_interval(x::Arb)

The ends of the interval enclosing the ball `x`, rounded outward at the precision of `x`.
"""
CertifiedRecords.write_interval(x::Arb) = CertifiedRecords.write_interval(getinterval(BigFloat, x)...)

end
