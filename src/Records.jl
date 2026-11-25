# The records an experiment writes and reads back: a header naming the run, one row per
# certified quantity, upper bounds printed so that the decimal written is itself an upper
# bound, and interval endpoints written so that they are read back exactly.
#
# checked: provenance -- SelfConsistentExperiments.provenance (src/sc/io.jl:88) records the
# commit of the package it lives in, from its own @__DIR__; run_header takes the calling
# package's module, which is the generalisation, and is named apart so the two can coexist
# until that package moves to this one.

export run_header, Upper, fmt_upper, write_endpoint, read_endpoint,
       open_record, append_record, read_record, recorded_keys, latest_record,
       upper_bound, write_upper, read_upper, write_interval, read_interval, read_double,
       SUMMARY_COLUMNS, summary_row, read_summary, save_environment

@doc raw"""
    run_header(mod, script; params...) -> String

The header a driver writes above its rows, as `#` lines: the script, the machine, the
time, the commit of the package `mod` and whether its working tree was clean, the Julia
version and the thread count, then the parameters of the run. A run whose commit is not
recorded cannot be repeated, and a run from a dirty tree says so.

`mod` is the package whose code produced the numbers, e.g. `DiffusionExperiments`; the
commit is read with `git -C pkgdir(mod)`, and `unknown` is written if that fails.
"""
function run_header(mod::Module, script::AbstractString; params...)
    root = pkgdir(mod)
    root === nothing && throw(ArgumentError("$mod is not a package"))
    commit = try readchomp(`git -C $root rev-parse --short HEAD`) catch; "unknown" end
    dirty = try !isempty(readchomp(`git -C $root status --porcelain`)) catch; true end
    buf = IOBuffer()
    println(buf, "# $script on $(gethostname()), ", Libc.strftime("%Y-%m-%dT%H:%M:%S", time()))
    println(buf, "# $(nameof(mod)) $commit", dirty ? " (working tree dirty)" : "",
            ", julia ", VERSION, ", ", Threads.nthreads(), " threads")
    isempty(params) || println(buf, "# ", join(["$k = $v" for (k, v) in pairs(params)], ", "))
    return String(take!(buf))
end

"""
    Upper(x)

Marks `x` as an upper bound in a row passed to [`append_record`](@ref), which then writes
it with [`fmt_upper`](@ref). Intervals are upper bounds through their supremum with no
marking, by the extensions for IntervalArithmetic and Arblib.
"""
struct Upper{T<:Real}
    x::T
end

@doc raw"""
    fmt_upper(x; digits = 7) -> String

`digits` significant digits of an upper bound, written so that the decimal written is at
least the bound. The bound `b` is converted to BigFloat exactly, multiplied by
``1 + 10^{1-d}`` (by ``1 - 10^{1-d}`` when ``b < 0``), ``d`` = `digits`, and rounded to nearest at
``d`` significant digits, which moves it by at most a relative ``\tfrac12 10^{1-d}``; so the
decimal is at least ``b(1 + 10^{1-d})(1 - \tfrac12 10^{1-d})(1 - 2^{-p}) \ge b`` at a precision
``p \ge 64`` for ``2 \le d \le 15`` (and symmetrically for ``b < 0``). The decimal exceeds the
bound by at most a relative ``\tfrac32 10^{1-d}``. For an interval, `b` is its supremum.
Anything else is written by `string`.
"""
fmt_upper(u::Upper; digits::Integer = 7) = _fmt_upper_big(_big_exact(u.x), digits)
fmt_upper(x; digits::Integer = 7) = string(x)

function _big_exact(x::AbstractFloat)
    b = BigFloat(x; precision = max(64, precision(x)))
    b == x || throw(ArgumentError("$x does not convert exactly to BigFloat"))
    return b
end
_big_exact(x::Integer) = BigFloat(x; precision = max(64, ndigits(x; base = 2) + 1))

function _fmt_upper_big(b::BigFloat, digits::Integer = 7)
    2 <= digits <= 15 || throw(ArgumentError("digits = $digits must be in 2:15"))
    isfinite(b) || return string(b)
    p = max(64, precision(b))
    return setprecision(BigFloat, p) do
        ε = BigFloat(10; precision = p)^(1 - digits)
        Printf.format(Printf.Format("%.$(digits - 1)e"), BigFloat(b; precision = p) * (b >= 0 ? 1 + ε : 1 - ε))
    end
end

@doc raw"""
    write_endpoint(x::AbstractFloat) -> (digits, bits)

An interval endpoint as the shortest decimal that gives `x` back at its own precision,
and that precision. [`read_endpoint`](@ref) inverts it exactly; reading the decimal at
any other precision does not, because the shortest decimal round-trips only at the
precision it was written for.  A subnormal `x` has fewer significant bits than its type,
and the shortest decimal that gives it back in that type is read at its precision as a
different number (`5.0e-324` against the double `4.94e-324`), so it is written as the
shortest decimal of the same number as a `BigFloat` of that precision.
"""
write_endpoint(x::AbstractFloat) = (string(x), precision(x))
write_endpoint(x::Union{Float16,Float32,Float64}) =
    (issubnormal(x) ? string(BigFloat(x; precision = precision(x))) : string(x), precision(x))

"""
    read_endpoint(digits, bits) -> BigFloat

The endpoint written by [`write_endpoint`](@ref), read at its own precision.
"""
read_endpoint(digits::AbstractString, bits::Integer) =
    BigFloat(digits; precision = Int(bits))
read_endpoint(digits::AbstractString, bits::AbstractString) =
    read_endpoint(digits, parse(Int, bits))

"""
    upper_bound(x, T = Float64) -> T

An upper bound on `x` in the floating-point type `T`: a real rounded up to `T`; an interval
of IntervalArithmetic through its supremum and an Arblib ball through the upper end of the
interval enclosing it, by the extensions.  `Inf` and `NaN` stay what they are.
"""
upper_bound(x::Real, ::Type{T} = Float64) where {T<:AbstractFloat} = T(x, RoundUp)

"""
    write_upper(x, T = Float64) -> (digits, bits)

An upper bound written exactly: [`upper_bound`](@ref) of `x` in `T`, written by
[`write_endpoint`](@ref), so that [`read_upper`](@ref) gives back that bound and not a
decimal near it.  [`fmt_upper`](@ref) prints seven digits for a person to read; this is
what a driver writes where the bound will be read back.
"""
write_upper(x, ::Type{T} = Float64) where {T<:AbstractFloat} = write_endpoint(upper_bound(x, T))

"""
    read_upper(digits, bits) -> BigFloat

An upper bound written by [`write_upper`](@ref), read back exactly at its own precision.
"""
read_upper(digits::AbstractString, bits) = read_endpoint(digits, bits)

"""
    write_interval(lo, hi) -> (lo_digits, hi_digits, bits)
    write_interval(x) -> (lo_digits, hi_digits, bits)

The two ends of an enclosure written by [`write_endpoint`](@ref), and their common
precision, for three columns of a record.  An interval of IntervalArithmetic is written
through its infimum and supremum and an Arblib ball through the interval enclosing it,
rounded outward at the precision of the ball, by the extensions.  A pair of `NaN`, which a
driver writes where it has no enclosure, is accepted; an inverted pair is not.
"""
function write_interval(lo::AbstractFloat, hi::AbstractFloat)
    precision(lo) == precision(hi) ||
        throw(ArgumentError("write_interval: the ends have precisions $(precision(lo)) and $(precision(hi))"))
    lo <= hi || (isnan(lo) && isnan(hi)) ||
        throw(ArgumentError("write_interval: $lo > $hi"))
    return (write_endpoint(lo)[1], write_endpoint(hi)[1], precision(lo))
end

"""
    read_interval(row, lo, hi, bits) -> (BigFloat, BigFloat)

The ends of an enclosure that a row of [`read_record`](@ref) holds in the columns `lo`, `hi`
and `bits`, read back exactly at their own precision.
"""
read_interval(row::AbstractDict, lo, hi, bits) =
    (read_endpoint(row[lo], row[bits]), read_endpoint(row[hi], row[bits]))

"""
    read_double(digits) -> Float64

A double a record holds, written in full: the decimal [`write_endpoint`](@ref) writes for it
at 53 bits, the one `string` writes, or a decimal exactly equal to it.  An error
if the decimal is not a double, so that a value rounded on the way into a record is not read
as though it had not been.  `Inf`, `-Inf` and `NaN` are read as themselves.
"""
function read_double(s::AbstractString)
    x = parse(Float64, s)
    (isnan(x) || isinf(x) || s == write_endpoint(x)[1] || s == string(x) ||
     BigFloat(s; precision = 1100) == x) ||
        throw(ArgumentError("read_double: $s is not a double written in full"))
    return x
end

"""
    SUMMARY_COLUMNS

The columns of a summary record, `quantity`, `kind`, `value` and `bits`; see
[`summary_row`](@ref).
"""
const SUMMARY_COLUMNS = ["quantity", "kind", "value", "bits"]

"""
    summary_row(quantity, kind, value) -> Vector{Any}

The columns of the record of the numbers a text quotes, and one row of it.  `kind` says what
the number is: `upper`, an upper bound, written as [`upper_bound`](@ref) of the value in its
own precision (a double for an Arblib ball or an interval); `lower`, a lower bound, and
`exact`, a value or a choice; `lo` and `hi`, an end of an enclosure; `count`, an integer.
Every float is written in full, with its precision in `bits`.
"""
function summary_row(q::AbstractString, kind::AbstractString, v)
    kind in ("upper", "lower", "exact", "lo", "hi", "count") ||
        throw(ArgumentError("summary_row: kind $kind"))
    # an Arblib ball is an AbstractFloat and is not a value written exactly: it goes through
    # upper_bound like an interval does
    plain = v isa Base.IEEEFloat || v isa BigFloat || v isa Integer || v isa AbstractString
    val = kind == "upper" && !plain ? upper_bound(v) : v
    plain || kind == "upper" ||
        throw(ArgumentError("summary_row: a $(typeof(v)) is written as an upper bound only"))
    return Any[q, kind, val isa AbstractFloat ? write_endpoint(val)[1] : val,
               val isa AbstractFloat ? precision(val) : ""]
end

"""
    read_summary(path) -> Dict{String,Any}

The numbers of a summary record written with [`summary_row`](@ref), by name: a float read
back exactly at the precision in its `bits` (a `BigFloat`), a count as an `Int`.
"""
function read_summary(path::AbstractString)
    out = Dict{String,Any}()
    for d in last(read_record(path))
        v = d["value"]
        out[d["quantity"]] = d["kind"] == "count" ? parse(Int, v) : read_endpoint(v, d["bits"])
    end
    return out
end

"""
    open_record(file, header, columns) -> Bool

Start `file` with `header` and the tab-separated `columns`, unless it already exists, in
which case nothing is written; returns whether it was created.
"""
function open_record(file::AbstractString, header::AbstractString, columns)
    isfile(file) && return false
    mkpath(dirname(abspath(file)))
    open(file, "w") do io
        print(io, header)
        println(io, join(columns, '\t'))
    end
    return true
end

"""
    append_record(file, row)

Append one row, each entry written by [`fmt_upper`](@ref): upper bounds, i.e. intervals
and values marked [`Upper`](@ref), as upper bounds, everything else as it is.
"""
append_record(file::AbstractString, row) =
    open(io -> println(io, join(fmt_upper.(row), '\t')), file, "a")

"""
    read_record(file) -> (header, rows)

The `#` lines of `file`, and its rows as `Dict{String,String}` keyed by column.
"""
function read_record(file::AbstractString)
    header = String[]
    cols = String[]
    rows = Dict{String,String}[]
    for line in eachline(file)
        if startswith(line, "#")
            push!(header, line)
        elseif isempty(cols)
            cols = String.(split(line, '\t'))
        elseif !isempty(line)
            vals = split(line, '\t')
            length(vals) == length(cols) ||
                error("$file: a row has $(length(vals)) fields against $(length(cols)) columns")
            push!(rows, Dict(c => String(v) for (c, v) in zip(cols, vals)))
        end
    end
    return header, rows
end

"""
    recorded_keys(file, columns...) -> Set{Tuple}

The values of `columns` in every row of `file`, as tuples of strings; empty if the file
does not exist. A driver's continue mode skips the keys already on record.
"""
function recorded_keys(file::AbstractString, columns::AbstractString...)
    isfile(file) || return Set{NTuple{length(columns),String}}()
    return Set(Tuple(d[c] for c in columns) for d in last(read_record(file)))
end

"""
    latest_record(dir, prefix; host = gethostname()) -> path

The record `dir/prefix.<commit>.<host>.tsv` written last, by modification time, among those of
every commit, where `<commit>` is the short hash `run_header` records (or `unknown`); an error if
there is none. A driver writes one record per commit, so a reader of another driver's results
should name the file this returns.
"""
function latest_record(dir::AbstractString, prefix::AbstractString; host::AbstractString = gethostname())
    ok(f) = startswith(f, prefix * ".") && endswith(f, ".$host.tsv") &&
            occursin(r"^[0-9a-z]+$", chop(f; head = ncodeunits(prefix) + 1, tail = ncodeunits(host) + 5))
    fs = filter(ok, readdir(dir))
    isempty(fs) && error("no record $prefix.<commit>.$host.tsv in $dir")
    return joinpath(dir, fs[argmax([mtime(joinpath(dir, f)) for f in fs])])
end

"""
    save_environment(record) -> String

Copy the `Manifest.toml` of the active project next to `record`, as
`<record without .tsv>.<time>.Manifest.toml`, and return its file name, for a driver to write
in a column of the rows it appends.  A dependency the Manifest gives by `path` (a working copy,
which the Manifest alone cannot reconstruct) is listed below the copy, as a TOML comment, with
the commit its checkout is at and whether its tracked files differ from it:

    # path RigorousInvariantMeasures /home/isaia/Code/RigorousInvariantMeasures.jl 87aed84 clean

so that every row names the exact versions of every package that produced it.  An error if the
active project has no Manifest.
"""
function save_environment(record::AbstractString)
    project = Base.active_project()
    project === nothing && error("save_environment: no active project")
    manifest = joinpath(dirname(project), "Manifest.toml")
    isfile(manifest) || error("save_environment: $manifest does not exist")
    base = endswith(record, ".tsv") ? record[1:end-4] : record
    file = "$base.$(Libc.strftime("%Y%m%dT%H%M%S", time())).Manifest.toml"
    lines = String[]
    current = ""
    for line in eachline(manifest)
        m = match(r"^\[\[deps\.(.+)\]\]$", strip(line))
        m === nothing || (current = m.captures[1])
        p = match(r"^\s*path\s*=\s*\"(.*)\"\s*$", line)
        if p !== nothing && p.captures[1] != "."
            dir = isabspath(p.captures[1]) ? p.captures[1] : normpath(joinpath(dirname(manifest), p.captures[1]))
            commit = try readchomp(`git -C $dir rev-parse --short HEAD`) catch; "unknown" end
            dirty = try !isempty(readchomp(`git -C $dir status --porcelain --untracked-files=no`)) catch; true end
            push!(lines, "# path $current $dir $commit $(dirty ? "dirty" : "clean")")
        end
    end
    mkpath(dirname(abspath(file)))
    open(file, "w") do io
        write(io, read(manifest, String))
        isempty(lines) || println(io, "\n# The dependencies given by path, at the commits of their checkouts:")
        foreach(l -> println(io, l), lines)
    end
    return basename(file)
end
