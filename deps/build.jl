using BinaryProvider
# Parse some basic command-line arguments
const verbose = "--verbose" in ARGS
const prefix = Prefix(get([a for a in ARGS if a != "--verbose"], 1, joinpath(@__DIR__, "usr")))
products = Product[
    LibraryProduct(prefix, "libmariadb", :libmariadb),
]
# Download binaries from hosted location
bin_prefix = "https://github.com/JuliaDatabases/MySQLBuilder/releases/download/v0.14"
# Listing of files generated by BinaryBuilder:
download_info = Dict(
    Linux(:aarch64, :glibc) => ("$bin_prefix/MySQL.aarch64-linux-gnu.tar.gz", "17901b7c08867304f4909c582d1d434326a6d91d76398b8dd411c6ed5379989b"),
    Linux(:armv7l, :glibc) => ("$bin_prefix/MySQL.arm-linux-gnueabihf.tar.gz", "0906fc0697fb9b7b19afda21408449f3e2f490f3cfb57947f8660ef305720422"),
    Linux(:i686, :glibc) => ("$bin_prefix/MySQL.i686-linux-gnu.tar.gz", "a5ff27bbedf7baba2e748a863023a7d4e3de7c730283c957e481ba1716248922"),
    Linux(:powerpc64le, :glibc) => ("$bin_prefix/MySQL.powerpc64le-linux-gnu.tar.gz", "17db7a12097fe54dfabb643d51f3798dc8821a2cb4cb9ee7fee8d9b89353f89d"),
    MacOS() => ("$bin_prefix/MySQL.x86_64-apple-darwin14.tar.gz", "ff0ab0f452171f1cd9309e38e468836a237da25752968ee3d12b7bcb867ebcd9"),
    Linux(:x86_64, :glibc) => ("$bin_prefix/MySQL.x86_64-linux-gnu.tar.gz", "6e85730e8e5a83923d6261dbb1eeef41499dd7452b4fe8f1790c476dcc626a63"),
    Windows(:i686) => ("$bin_prefix/MySQL.i686-w64-mingw32.tar.gz", "316af0c159384fa94a24aa0439b7335c615a30d131415c9beb8069b2cbfd086c"),
    Windows(:x86_64) => ("$bin_prefix/MySQL.x86_64-w64-mingw32.tar.gz", "578409ddbf9ebf6aab55a67833736ece56612aed2d614eefc81ec3aef77e17fd"),
)

# First, check to see if we're all satisfied
if any(!satisfied(p; verbose=verbose) for p in products)
    if haskey(download_info, platform_key())
        # Download and install binaries
        url, tarball_hash = download_info[platform_key()]
        install(url, tarball_hash; prefix=prefix, force=true, verbose=true, ignore_platform=true)
        try
            @show readdir(prefix.path)
            @show readdir(joinpath(prefix.path, "lib"))
            @show readdir(joinpath(prefix.path, "bin"))
        end
    else
        # If we don't have a BinaryProvider-compatible .tar.gz to download, complain.
        # Alternatively, you could attempt to install from a separate provider,
        # build from source or something more even more ambitious here.
        error("Your platform $(Sys.MACHINE) is not supported by this package!")
    end
end
# Write out a deps.jl file that will contain mappings for our products
write_deps_file(joinpath(@__DIR__, "deps.jl"), products)
