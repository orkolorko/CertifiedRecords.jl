using CertifiedRecords
using CertifiedRecords: _json_data
import HTTP
using Test
import JSON

@testset "checksums" begin
    f = tempname()
    write(f, "abc")
    @test file_checksum(f, "MD5") == "900150983cd24fb0d6963f7d28e17f72"
    @test file_checksum(f, "SHA-1") == "a9993e364706816aba3e25717850c26c9cd0d89d"
    @test file_checksum(f, "SHA-256") ==
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    @test_throws ArgumentError file_checksum(f, "CRC32")
end

@testset "token file" begin
    f = tempname()
    write(f, "  abc-123\n")
    @test CertifiedRecords._headers(f) == ["X-Dataverse-key" => "abc-123"]
    @test isempty(CertifiedRecords._headers(nothing))
    @test_throws ErrorException CertifiedRecords._headers(f * ".none")
    withenv("DATAVERSE_TOKEN_FILE" => f) do
        @test default_token_file() == f
    end
    withenv("DATAVERSE_TOKEN_FILE" => nothing) do
        @test default_token_file() == joinpath(homedir(), ".config", "wtools", "dataverse-token")
    end
end

@testset "listing and request bodies" begin
    # one file of doi:10.7910/DVN/OZQMD4 as the Harvard installation listed it on 2026-11-20
    listed = JSON.parse("""{"label": "heat_sink_fem_simulation_results.mat", "restricted": false,
        "version": 1, "datasetVersionId": 444540,
        "dataFile": {"id": 11253959, "filename": "heat_sink_fem_simulation_results.mat",
          "filesize": 161748064, "md5": "701e7677a7f26927393e8bd69ac123bf",
          "checksum": {"type": "MD5", "value": "701e7677a7f26927393e8bd69ac123bf"},
          "tabularData": false}}""")
    f = DataverseFile(listed)
    @test f.id == 11253959 && f.label == "heat_sink_fem_simulation_results.mat"
    @test f.directory == "" && f.size == 161748064 && !f.tabular
    @test (f.checksum_type, f.checksum) == ("MD5", "701e7677a7f26927393e8bd69ac123bf")

    d = JSON.parse(_json_data("data/example1", "Lanford"))
    @test d["tabIngest"] == "false" && d["restrict"] == "false"
    @test d["directoryLabel"] == "data/example1" && d["description"] == "Lanford"
    @test !haskey(JSON.parse(_json_data("", "")), "directoryLabel")
    r = JSON.parse(_json_data("data", ""; replace = true))
    @test r["forceReplace"] == false && !haskey(r, "restrict")
end

@testset "download: a failed transfer or a wrong checksum leaves dest as it was" begin
    body = "certified\n"
    srv = HTTP.serve!(_ -> HTTP.Response(200, body), "127.0.0.1", 0)
    port = HTTP.port(srv)
    try
        dir = mktempdir()
        dest = joinpath(dir, "rec.tsv")
        write(dest, "previous")
        good = DataverseFile(1, "rec.tsv", "", sizeof(body), "MD5",
                             bytes2hex(CertifiedRecords.MD5.md5(body)), false)
        bad = DataverseFile(1, "rec.tsv", "", sizeof(body), "MD5", "0"^32, false)
        @test_throws ErrorException dataverse_download(bad, dest; server = "http://127.0.0.1:$port")
        @test read(dest, String) == "previous" && readdir(dir) == ["rec.tsv"]
        @test_throws Exception dataverse_download(good, dest; server = "http://127.0.0.1:1")
        @test read(dest, String) == "previous" && readdir(dir) == ["rec.tsv"]
        @test dataverse_download(good, dest; server = "http://127.0.0.1:$port") == dest
        @test read(dest, String) == body && readdir(dir) == ["rec.tsv"]
    finally
        close(srv)
    end
end

# Read-only calls to dataverse.harvard.edu on two published datasets; set
# CERTIFIEDRECORDS_LIVE=1 to run them. Nothing is written to the installation.
if get(ENV, "CERTIFIEDRECORDS_LIVE", "0") == "1"
    @testset "live, read-only" begin
        dir = mktempdir()
        fs = dataverse_files("doi:10.7910/DVN/1QJCDJ")
        f = only(filter(x -> x.id == 11592657, fs))
        @test f.label == "SPID_v1.2_network.R" && !f.tabular
        p = dataverse_download(f, joinpath(dir, f.label))
        @test filesize(p) == f.size
        # an ingested tabular file: its checksum is of the file as uploaded
        t = only(filter(x -> x.id == 4880210, dataverse_files("doi:10.7910/DVN/CVYSR7")))
        @test t.tabular
        q = dataverse_download(t, joinpath(dir, "original"))
        @test file_checksum(q, t.checksum_type) == t.checksum
    end
end

# Writes to an installation: set CERTIFIEDRECORDS_LIVE_WRITE=1 and CERTIFIEDRECORDS_SCRATCH_DOI
# to the persistent id of a dataset whose draft may be written to, with the token in
# default_token_file() (or DATAVERSE_TOKEN_FILE). One small file is added to the draft under
# certifiedrecords-test/, downloaded back, compared byte for byte and deleted again; nothing
# is published.
if get(ENV, "CERTIFIEDRECORDS_LIVE_WRITE", "0") == "1"
    @testset "live, add and download on a scratch draft" begin
        doi, tok = ENV["CERTIFIEDRECORDS_SCRATCH_DOI"], default_token_file()
        dir = mktempdir()
        src = joinpath(dir, "certifiedrecords_test_$(time_ns()).tsv")
        write(src, "x\tlo\thi\n0.1\t0x1.9999999999999p-4\t0x1.999999999999ap-4\n")
        f = dataverse_add(doi, src; directory = "certifiedrecords-test", token_file = tok)
        try
            @test f.label == basename(src) && f.directory == "certifiedrecords-test"
            @test f.size == filesize(src) && !f.tabular
            listed = only(filter(x -> x.id == f.id, dataverse_files(doi; version = ":draft", token_file = tok)))
            @test listed.checksum == f.checksum && listed.directory == "certifiedrecords-test"
            back = dataverse_download(listed, joinpath(dir, "back.tsv"); token_file = tok)
            @test read(back) == read(src)
        finally
            HTTP.delete("$(DATAVERSE_HARVARD)/api/files/$(f.id)", CertifiedRecords._headers(tok))
        end
        @test !any(x -> x.id == f.id, dataverse_files(doi; version = ":draft", token_file = tok))
    end
end
