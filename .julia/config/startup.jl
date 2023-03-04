using Pkg
Pkg.add("Revise")
Pkg.add("OhMyREPL")
Pkg.add("PkgTemplates")
using Revise
using OhMyREPL
colorscheme!("OneDark")
enable_autocomplete_brackets(false)

function template()
    @eval begin
        using PkgTemplates
        Template(;  user="brendanjohnharris",
                    dir="./",
                    julia=v"1.6.0",
                    plugins=[   ProjectFile(),
                                SrcDir(),
                                Tests(; project=true),
                                Readme(),
                                License(),
                                Git(;ignore=["*.code-workspace", "*.mat", "*.csv", "*.parquet", "*.jld2", "data/**", "*.jl.cov", "*.jl.*.cov", "*.jl.mem", "docs/build/", "docs/site/, LocalPreferences.toml"]),
                                CompatHelper(),
                                TagBot(),
                                GitHubActions(; linux=true, osx=true, windows=true, x86=true, extra_versions=["1.6", "1", "nightly"]),
                                Codecov(),
                                Documenter{NoDeploy}()])
    end
end
