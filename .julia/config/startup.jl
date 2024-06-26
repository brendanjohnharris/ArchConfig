using Pkg
#ENV["PYTHON"] = "python3.9"
#ENV["JULIA_PYTHONCALL_EXE"]="@PyCall"
# ENV["FORESIGHT_PATCHES"] = true
using Revise
using OhMyREPL
using CUDA
using Infiltrator
using Downloads
colorscheme!("OneDark")
enable_autocomplete_brackets(false)

function template()
    @eval begin
        using PkgTemplates
        stylefile = tempname()
        Downloads.download("https://gist.githubusercontent.com/brendanjohnharris/182f2deec122d16d28218d39ebecc9c8/raw/744b9950af52a949cb9bd4c6df4351d049cc37ca/.JuliaFormatter.toml", stylefile)
        Template(; user="brendanjohnharris",
            dir="./",
            julia=v"1.9.0",
            plugins=[ProjectFile(),
                SrcDir(),
                Tests(; project=true),
                Readme(),
                License(),
                Git(; ignore=["*.code-workspace", "*.mat", "*.csv", "*.parquet", "*.jld2", "data", "*.jl.cov", "*.jl.*.cov", "*.jl.mem", "lcov*.info", "docs/build/", "docs/site/", "LocalPreferences.toml", ".CondaPkg/", "Artifacts.toml", "Manifest.toml", ".vscode"]),
                # CompatHelper(),
                TagBot(),
                GitHubActions(; linux=true, osx=true, windows=true, x86=true, extra_versions=["1.9", "nightly"]),
                Codecov(),
                Documenter{GitHubActions}(),
                Dependabot(),
                RegisterAction(),
                Formatter(; file=stylefile)],)
    end
end
