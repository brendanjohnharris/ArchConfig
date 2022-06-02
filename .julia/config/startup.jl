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
                                Git(;ignore=["*.code-workspace"]),
                                CompatHelper(),
                                TagBot(),
                                GitHubActions(),
                                Codecov()])
    end
end
