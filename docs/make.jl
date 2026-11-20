using CertifiedRecords
using Documenter

DocMeta.setdocmeta!(CertifiedRecords, :DocTestSetup, :(using CertifiedRecords); recursive=true)

makedocs(;
    modules=[CertifiedRecords],
    authors="Isaia Nisoli",
    sitename="CertifiedRecords.jl",
    format=Documenter.HTML(;
        canonical="https://orkolorko.github.io/CertifiedRecords.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/orkolorko/CertifiedRecords.jl",
    devbranch="main",
)
