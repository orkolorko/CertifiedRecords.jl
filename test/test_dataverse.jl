using CertifiedRecords
using CertifiedRecords: _json_data
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

@testset "token" begin
    f = tempname()
    write(f, "  abc-123\n")
    @test dataverse_token(f) == "abc-123"
    @test_throws ErrorException dataverse_token(f * ".none")
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
