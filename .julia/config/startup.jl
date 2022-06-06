function template()
    @eval begin
        using PkgTemplates
        Template(;  user="brendanjohnharris",
                    dir="./",
                    julia=v"1.5.0",
                    plugins=[   ProjectFile(),
                                SrcDir(),
                                Tests(; project=true),
                                Readme(),
                                License(),
                                Git(;ignore=["*.code-workspace", "*.mat", "*.csv", "*.parquet", "*.jld2", "data/**"]),
                                CompatHelper(),
                                TagBot(),
                                GitHubActions(; linux=true, osx=true, windows=true, x86=true, extra_versions=["1.6", "1.7", "nightly"]),
                                Codecov()])
    end
end
