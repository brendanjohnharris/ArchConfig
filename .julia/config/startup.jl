pkgs = [:Pkg,
    :Revise,
    :OhMyREPL,
    :Infiltrator,
    :Downloads,
    :TestEnv,
    :PkgTemplates]

printout = false
if false
    using Term
    function make_line(pkg, time)
        status = isnothing(time) ? "{bold yellow}•{/bold yellow}" : "{bold green}✔{/bold green}"
        out = status * " $pkg"
        if !isnothing(time)
            time, compile, recompile = time
            out = out * ": $(time)s ($(compile)s compile, $(recompile)s recompile)"
        end
        return out
    end
    function _make_panel(pkgs, times)
        out = map(pkgs, times) do pkg, time
            make_line(pkg, time)
        end
        out = ["{bold bright_blue}Startup packages{/bold bright_blue}", out...]
        out = join(out, "\n")
    end
    function make_panel(pkgs, times)
        out = _make_panel(pkgs, times)
        Term.TextWidget(out; as_panel=false)
    end
    times = fill(nothing, length(pkgs)) |> Vector{Any}
    app = Term.App(make_panel(pkgs, times))
    display(app |> Term.frame)
    map(pkgs, times) do pkg, time
        t = @timed eval(:(using $pkg))
        ts = getindex.([t], [:time, :compile_time, :recompile_time])
        ts = round.(ts; sigdigits=1)
        times[pkgs.==pkg] .= [ts]
        Term.LiveWidgets.erase!(app)
        app.widgets[:A].text = _make_panel(pkgs, times)
    end
    return nothing
else
    map(pkgs) do pkg
        printout && print("$pkg: ")
        t = @timed eval(:(using $pkg))
        time = round(t[:time]; sigdigits=1)
        compile = round(t[:compile_time]; sigdigits=1)
        recompile = round(t[:recompile_time]; sigdigits=1)
        printout && print("$(time)s ($(compile)s compile, $(recompile)s recompile)\n")
    end
    return nothing
end



#homeenv = Base.current_project()
#Pkg.activate()
#ENV["PYTHON"] = "python3.9"
#ENV["JULIA_PYTHONCALL_EXE"]="@PyCall"
# ENV["FORESIGHT_PATCHES"] = true
# ENV["JULIA_CONDAPKG_EXE"] = "/opt/miniconda3/bin/conda"
ENV["JULIA_CONDAPKG_OFFLINE"] = true
ENV["JULIA_CONDAPKG_BACKEND"] = "MicroMamba"
ENV["DRWATSON_STOREPATCH"] = true
colorscheme!("OneDark")
enable_autocomplete_brackets(false)
#Pkg.update()
#Pkg.activate(homeenv)

function template()
    @eval begin
        stylefile = tempname()
        Downloads.download("https://gist.githubusercontent.com/brendanjohnharris/182f2deec122d16d28218d39ebecc9c8/raw/744b9950af52a949cb9bd4c6df4351d049cc37ca/.JuliaFormatter.toml", stylefile)
        Template(; user="brendanjohnharris",
            dir="./",
            julia=v"1.10.0",
            plugins=[ProjectFile(),
                SrcDir(),
                Tests(; project=true),
                Readme(),
                License(),
                Git(; ignore=["*.code-workspace", "*.mat", "*.csv", "*.parquet", "*.jld2", "data", "*.jl.cov", "*.jl.*.cov", "*.jl.mem", "lcov*.info", "docs/build/", "docs/site/", "LocalPreferences.toml", ".CondaPkg/", "Artifacts.toml", "Manifest.toml", ".vscode"]),
                # CompatHelper(),
                TagBot(),
                GitHubActions(; linux=true, osx=true, windows=true, x86=true, extra_versions=["1.10", "nightly"]),
                Codecov(),
                Documenter{GitHubActions}(),
                Dependabot(),
                RegisterAction(),
                Formatter(; file=stylefile)],)
    end
end
