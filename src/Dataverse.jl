# Depositing records on a Dataverse installation and fetching them back, through its native
# API (Dataverse API Guide v6.12): listing the files of a dataset version, downloading one
# with its checksum verified, adding a file to a dataset and replacing one. Publishing a
# version is left to the web interface on purpose: it makes the deposit public and permanent.
#
# A record is deposited byte for byte: files are added with `"tabIngest": "false"`, which
# skips Dataverse's tabular ingest, so a TSV is not converted to its own tabular format.

export DATAVERSE_HARVARD, DataverseFile, default_token_file, dataverse_files,
       dataverse_download, dataverse_add, dataverse_delete, file_checksum
# dataverse_replace is not exported until it has been run against an installation; see its
# docstring. dataverse_add was first run on 2026-11-20, 49 files into the draft of
# doi:10.7910/DVN/OWADFA on dataverse.harvard.edu, each downloaded back byte for byte.

const DATAVERSE_HARVARD = "https://dataverse.harvard.edu"

"""
    default_token_file() -> String

The path of the API token file: `\$DATAVERSE_TOKEN_FILE` if set, otherwise
`~/.config/wtools/dataverse-token`, the file `wnew --dataverse` reads. Every function of
this package takes the token as the path of such a file (`token_file`), never as a string:
the token is read only to build the request header, so it is not held by the caller and
cannot be printed or logged from there. A token is specific to one installation.
"""
default_token_file() = get(ENV, "DATAVERSE_TOKEN_FILE",
                           joinpath(homedir(), ".config", "wtools", "dataverse-token"))

function _read_token(file::AbstractString)
    isfile(file) || error("no Dataverse API token file at $file")
    return strip(read(file, String))
end

"""
    DataverseFile

One file of a dataset version, as the native API lists it: the datafile `id`, the `label`
(its name in the dataset), the `directory` (`directoryLabel`, empty if none), the `size`
in bytes, the checksum `checksum_type` and `checksum`, and whether Dataverse ingested it as
`tabular`, in which case `checksum` is that of the file as uploaded.
"""
struct DataverseFile
    id::Int
    label::String
    directory::String
    size::Int
    checksum_type::String
    checksum::String
    tabular::Bool
end

function DataverseFile(f::AbstractDict)
    d = f["dataFile"]
    return DataverseFile(d["id"], f["label"], get(f, "directoryLabel", ""), d["filesize"],
                         d["checksum"]["type"], d["checksum"]["value"],
                         get(d, "tabularData", false))
end

_headers(token_file) = token_file === nothing ? Pair{String,String}[] :
                       ["X-Dataverse-key" => _read_token(token_file)]

function _json(r)
    d = JSON.parse(String(r.body))
    get(d, "status", "") == "OK" || error("Dataverse: $(get(d, "message", d))")
    return d["data"]
end

"""
    dataverse_files(doi; version = ":latest-published", server, token_file = nothing)

The files of one version of the dataset `doi` (e.g. `"doi:10.7910/DVN/XXXXXX"`), as
[`DataverseFile`](@ref)s. `version` is `":latest-published"`, `":latest"` (the draft if
there is one), `":draft"` or a number such as `"1.0"`; a draft needs a `token_file`, e.g.
[`default_token_file()`](@ref).
"""
function dataverse_files(doi::AbstractString; version::AbstractString = ":latest-published",
                         server::AbstractString = DATAVERSE_HARVARD, token_file = nothing)
    url = "$server/api/datasets/:persistentId/versions/$version"
    r = HTTP.get(url, _headers(token_file);
                 query = ["persistentId" => doi, "excludeFiles" => "false"])
    return [DataverseFile(f) for f in _json(r)["files"]]
end

"""
    file_checksum(path, type) -> String

The checksum of the file at `path`, in lower-case hexadecimal, for the checksum `type`
Dataverse reports: `"MD5"`, `"SHA-1"`, `"SHA-256"` or `"SHA-512"`.
"""
function file_checksum(path::AbstractString, type::AbstractString)
    h = type == "MD5"     ? MD5.md5 :
        type == "SHA-1"   ? SHA.sha1 :
        type == "SHA-256" ? SHA.sha256 :
        type == "SHA-512" ? SHA.sha512 :
        throw(ArgumentError("unknown checksum type $type"))
    return bytes2hex(open(h, path))
end

"""
    dataverse_download(f::DataverseFile, dest; server, token_file = nothing) -> dest

Download `f` to the path `dest` and verify its size and checksum against the listing;
an ingested tabular file is downloaded in its original uploaded form (`format=original`),
the one the checksum is of. The download goes to a temporary file beside `dest`, which is
moved onto `dest` only once it verifies; if the transfer fails or the file does not verify,
the temporary file is removed, `dest` is left as it was, and an error is raised.
"""
function dataverse_download(f::DataverseFile, dest::AbstractString;
                            server::AbstractString = DATAVERSE_HARVARD, token_file = nothing)
    url = "$server/api/access/datafile/$(f.id)"
    query = f.tabular ? ["format" => "original"] : Pair{String,String}[]
    dir = dirname(abspath(dest))
    mkpath(dir)
    tmp, io = mktemp(dir)
    try
        try
            HTTP.get(url, _headers(token_file); query = query, response_stream = io)
        finally
            close(io)
        end
        got = file_checksum(tmp, f.checksum_type)
        (got == f.checksum && (f.tabular || filesize(tmp) == f.size)) ||
            error("$(f.label): downloaded $(f.checksum_type) $got and $(filesize(tmp)) bytes, listed $(f.checksum) and $(f.size)")
        mv(tmp, dest; force = true)
    finally
        rm(tmp; force = true)
    end
    return dest
end

# the jsonData of an add or a replace; directory and description are optional
function _json_data(directory, description; replace = false)
    d = Dict{String,Any}("description" => description, "tabIngest" => "false",
                         "restrict" => "false")
    isempty(directory) || (d["directoryLabel"] = directory)
    replace && (delete!(d, "restrict"); d["forceReplace"] = false)
    return JSON.json(d)
end

function _upload(url, path, json, token_file)
    f = open(path) do io
        form = HTTP.Form(["file" => HTTP.Multipart(basename(path), io, "application/octet-stream"),
                          "jsonData" => json])
        DataverseFile(only(_json(HTTP.post(url, _headers(token_file), form))["files"]))
    end
    got = file_checksum(path, f.checksum_type)
    (got == f.checksum && f.size == filesize(path)) ||
        error("$(f.label): Dataverse stored $(f.checksum_type) $(f.checksum) and $(f.size) bytes, the local file has $got and $(filesize(path))")
    return f
end

"""
    dataverse_add(doi, path; directory = "", description = "", server, token_file) -> DataverseFile

Add the file at `path` to the draft of dataset `doi`, under `directory` in the dataset,
with tabular ingest skipped so that it is stored byte for byte; the checksum Dataverse
reports is compared with the local one. Creates a draft version if the dataset has none.
Nothing is published. The size Dataverse reports is compared with the local one as well.

Run against dataverse.harvard.edu on 2026-11-20 (49 files, directory labels of two levels,
no tabular ingest), and exercised by the token-gated live test.
"""
function dataverse_add(doi::AbstractString, path::AbstractString;
                       directory::AbstractString = "", description::AbstractString = "",
                       server::AbstractString = DATAVERSE_HARVARD,
                       token_file::AbstractString = default_token_file())
    url = "$server/api/datasets/:persistentId/add?persistentId=$(HTTP.escapeuri(doi))"
    return _upload(url, path, _json_data(directory, description), token_file)
end

"""
    dataverse_replace(f::DataverseFile, path; description = "", server, token_file) -> DataverseFile

Replace the deposited file `f` with the file at `path`, in the draft. Dataverse does not
carry the directory and description of `f` over to the replacement (API Guide, "Replacing
Files"); `f.directory` is passed as `directoryLabel` in the request, which the Guide
documents for adding a file but not for replacing one, so whether it is applied has to be
checked on the installation. The checksum is compared as in [`dataverse_add`](@ref).
Nothing is published. Not yet run against an installation, as [`dataverse_add`](@ref).
"""
function dataverse_replace(f::DataverseFile, path::AbstractString;
                           description::AbstractString = "",
                           server::AbstractString = DATAVERSE_HARVARD,
                           token_file::AbstractString = default_token_file())
    url = "$server/api/files/$(f.id)/replace"
    return _upload(url, path, _json_data(f.directory, description; replace = true), token_file)
end

"""
    dataverse_delete(f::DataverseFile; server, token_file) -> nothing

Delete the file `f` (by its datafile `id`, as [`dataverse_files`](@ref) lists it) from the draft
of its dataset: `DELETE /api/files/{id}` of the native API (API Guide, "Deleting Files").  An
error unless Dataverse answers OK.  Nothing is published.  The same call removes the file added by
the token-gated live test of [`dataverse_add`](@ref) at its end.
"""
function dataverse_delete(f::DataverseFile; server::AbstractString = DATAVERSE_HARVARD,
                          token_file::AbstractString = default_token_file())
    _json(HTTP.request("DELETE", "$server/api/files/$(f.id)", _headers(token_file)))
    return nothing
end
