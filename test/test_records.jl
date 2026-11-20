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
