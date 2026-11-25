using CertifiedRecords
using CertifiedRecords: _json_data
using Test
using IntervalArithmetic: interval
using Arblib: Arb, getinterval

@testset "run_header" begin
    h = run_header(CertifiedRecords, "driver"; N = 64, rho = 3.75)
    lines = split(chomp(h), '\n')
    @test length(lines) == 3
    @test startswith(lines[1], "# driver on $(gethostname()), ")
    @test startswith(lines[2], "# CertifiedRecords ")
    @test occursin("julia $(VERSION)", lines[2])
    @test lines[3] == "# N = 64, rho = 3.75"
    @test_throws ArgumentError run_header(Base.Math, "driver")
end

@testset "fmt_upper writes an upper bound" begin
    check(b, s) = (v = parse(BigFloat, s; precision = 2048); v >= b && v <= b * (1 + big"2e-6"))
    setprecision(BigFloat, 512) do
        for x in (big"1.23456749999999999999", big"9.9999995", big(1) / 3, big"1e-300" / 7,
                  big"3.677076e0" + big"1e-40", big"7e300")
            @test check(x, fmt_upper(Upper(x)))
            @test check(x, fmt_upper(interval(BigFloat, x)))
        end
    end
    for x in (0.1, 1 / 3, 6.02e23, 2.2250738585072014e-308)
        @test check(big(x), fmt_upper(Upper(x)))
        @test check(big(x), fmt_upper(interval(x)))
    end
    @test check(big(123456789), fmt_upper(Upper(123456789)))
    a = Arb(1) / 3
    @test check(getinterval(BigFloat, a)[2], fmt_upper(a))
    @test parse(BigFloat, fmt_upper(a)) >= 1 / big(3)
    @test fmt_upper(Upper(Inf)) == "Inf"
    @test fmt_upper(7) == "7"
    @test fmt_upper("x2") == "x2"
end

@testset "endpoints round-trip exactly" begin
    for bits in (53, 512, 1280)
        x = setprecision(BigFloat, bits) do
            BigFloat(2) / 7 + BigFloat(2)^(-bits ÷ 2)
        end
        d, b = write_endpoint(x)
        @test b == bits
        y = read_endpoint(d, string(b))
        @test y == x && precision(y) == bits
    end
    d, b = write_endpoint(0.1)
    @test read_endpoint(d, b) == 0.1
    # a subnormal double: its shortest decimal, 5.0e-324, is another number at 53 bits
    for x in (5e-324, -3 * 5e-324, floatmin(Float64) / 3)
        d, b = write_endpoint(x)
        @test read_endpoint(d, b) == x && parse(Float64, d) === x
    end
end

@testset "records" begin
    dir = mktempdir()
    f = joinpath(dir, "sub", "r.tsv")
    h = run_header(CertifiedRecords, "t")
    @test open_record(f, h, ["obs", "N", "bound"])
    @test !open_record(f, h, ["obs", "N", "bound"])
    append_record(f, Any[:x2, 64, Upper(2.0)])
    append_record(f, Any[:cos, 128, interval(BigFloat, 3)])
    header, rows = read_record(f)
    @test length(header) == 2
    @test rows[1] == Dict("obs" => "x2", "N" => "64", "bound" => fmt_upper(Upper(2.0)))
    @test recorded_keys(f, "obs", "N") == Set([("x2", "64"), ("cos", "128")])
    @test isempty(recorded_keys(joinpath(dir, "none.tsv"), "N"))
    open(io -> println(io, "x\t1"), f, "a")
    @test_throws ErrorException read_record(f)
end

@testset "latest record" begin
    d = mktempdir()
    for (f, t) in (("ex.lanford.abc1234.host1.tsv", 1), ("ex.lanford.def5678.host1.tsv", 3),
                   ("ex.lanford.0123abc.host2.tsv", 5), ("ex.lanford_noise.9999999.host1.tsv", 7),
                   ("ex.lanford.x.y.host1.tsv", 9))
        write(joinpath(d, f), "")
        run(`touch -d @$(1_700_000_000 + t) $(joinpath(d, f))`)
    end
    @test basename(latest_record(d, "ex.lanford"; host = "host1")) == "ex.lanford.def5678.host1.tsv"
    @test basename(latest_record(d, "ex.lanford"; host = "host2")) == "ex.lanford.0123abc.host2.tsv"
    @test basename(latest_record(d, "ex.lanford_noise"; host = "host1")) == "ex.lanford_noise.9999999.host1.tsv"
    @test_throws ErrorException latest_record(d, "ex.doubling"; host = "host1")
end

@testset "save_environment" begin
    env = mktempdir(); dep = mktempdir()
    run(pipeline(`git -C $dep init -q`, devnull)); write(joinpath(dep, "f"), "x")
    run(`git -C $dep add f`); run(`git -C $dep -c user.name=t -c user.email=t@t commit -q -m c`)
    commit = readchomp(`git -C $dep rev-parse --short HEAD`)
    write(joinpath(env, "Project.toml"), "name = \"E\"\n")
    write(joinpath(env, "Manifest.toml"), """
        [[deps.Dep]]
        path = "$dep"
        uuid = "00000000-0000-0000-0000-000000000001"

        [[deps.Own]]
        path = "."
        """)
    old = Base.active_project()
    try
        Base.set_active_project(joinpath(env, "Project.toml"))
        rec = joinpath(mktempdir(), "x.abc123.host.tsv")
        name = save_environment(rec)
        @test startswith(name, "x.abc123.host.") && endswith(name, ".Manifest.toml")
        text = read(joinpath(dirname(rec), name), String)
        @test startswith(text, read(joinpath(env, "Manifest.toml"), String))
        @test occursin("# path Dep $dep $commit clean", text) && !occursin("# path Own", text)
        write(joinpath(dep, "f"), "y")
        @test occursin("$commit dirty", read(joinpath(dirname(rec), save_environment(rec * "2")), String))
    finally
        Base.set_active_project(old)
    end
end

@testset "upper bounds written exactly" begin
    @test upper_bound(0.1) === 0.1
    @test upper_bound(big(1) / 3) >= big(1) / 3 && upper_bound(big(1) / 3) isa Float64
    @test upper_bound(big(1) / 3) == nextfloat(Float64(big(1) / 3, RoundDown))
    @test upper_bound(interval(1, 2)) === 2.0
    a = Arb(1) / 3
    @test upper_bound(a) >= getinterval(BigFloat, a)[2]
    @test upper_bound(a) == Float64(getinterval(BigFloat, a)[2], RoundUp)
    @test isinf(upper_bound(Inf)) && isnan(upper_bound(NaN))
    for x in (0.1, 1 / 3, 6.02e23, 5e-324, 1.7976931348623157e308)
        d, b = write_upper(x)
        @test b == 53 && read_upper(d, b) == x && read_double(d) === x
    end
    d, b = write_upper(a)
    @test read_upper(d, b) == upper_bound(a)
    d, b = write_upper(a, BigFloat)
    @test b == precision(BigFloat) && read_upper(d, b) >= getinterval(BigFloat, a)[2]
end

@testset "intervals written exactly" begin
    lo, hi, b = write_interval(0.1, 0.3)
    @test (lo, hi, b) == ("0.1", "0.3", 53)
    r = Dict("l" => lo, "h" => hi, "b" => string(b))
    @test read_interval(r, "l", "h", "b") == (big(0.1), big(0.3))
    a = Arb("0.285"; prec = 256)
    lo, hi, b = write_interval(a)
    @test b == 256
    L, H = read_interval(Dict("l" => lo, "h" => hi, "b" => string(b)), "l", "h", "b")
    @test (L, H) == getinterval(BigFloat, a) && L <= big"0.285" <= H
    @test write_interval(interval(1, 2))[1:2] == ("1.0", "2.0")
    @test write_interval(NaN, NaN)[1] == "NaN"
    @test_throws ArgumentError write_interval(2.0, 1.0)
    @test_throws ArgumentError write_interval(1.0, big(2.0))
end

@testset "read_double" begin
    @test read_double("0.30000000000000004") === 0.1 + 0.2
    @test read_double("0.5") === 0.5 && read_double("0.50") === 0.5
    @test read_double("Inf") === Inf && isnan(read_double("NaN"))
    @test_throws ArgumentError read_double("0.3000000000000000")
    @test_throws ArgumentError read_double("1.234567e-01")
end

@testset "summary records" begin
    f = joinpath(mktempdir(), "s.tsv")
    open_record(f, "# t\n", SUMMARY_COLUMNS)
    a = Arb(1) / 3
    for row in (summary_row("n", "count", 7), summary_row("r", "upper", a),
                summary_row("x", "exact", 0.1), summary_row("l", "lo", big(1) / 7),
                summary_row("u", "upper", 2.5))
        append_record(f, row)
    end
    s = read_summary(f)
    @test s["n"] === 7 && s["x"] == 0.1 && s["u"] == 2.5
    @test s["r"] == upper_bound(a) && s["r"] >= 1 / big(3)
    @test s["l"] == big(1) / 7 && precision(s["l"]) == precision(BigFloat)
    @test_throws ArgumentError summary_row("q", "nearly", 1.0)
end

@testset "fmt_upper with fewer digits, and below zero" begin
    setprecision(BigFloat, 512) do
        for d in (2, 3, 4, 7), x in (0.0066701783, 1 / 3, 6.02e23, 2.2250738585072014e-308, 0.012)
            s = fmt_upper(Upper(x); digits = d)
            v = parse(BigFloat, s; precision = 2048)
            @test v >= big(x)
            # the least such decimal: one unit less in the last digit is below the bound
            mant, ex = split(s, 'e')
            unit = big(10.0)^(parse(Int, ex) - (d - 1))
            @test v - unit < big(x)
            @test length(split(split(s, 'e')[1], '.')[2]) == d - 1
        end
        @test parse(BigFloat, fmt_upper(Upper(-0.0123); digits = 3)) >= big(-0.0123)
        @test fmt_upper(Upper(3.81495); digits = 3) == "3.82e+00"
        @test fmt_upper(Upper(9.996); digits = 3) == "1.00e+01"
        @test fmt_upper(Upper(-0.0123); digits = 3) == "-1.23e-02"
    end
    @test_throws ArgumentError fmt_upper(Upper(1.0); digits = 1)
end
