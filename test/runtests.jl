using Pkg: Pkg
using Ensembles
using Test
using TestReports
using Aqua
using Documenter

function run_and_find_stale_deps(root_project_path::String; ignore::AbstractVector{Symbol} = Symbol[])
    prj = Aqua.TOML.parsefile(joinpath(root_project_path, "Project.toml"))
    deps = [Base.PkgId(Base.UUID(v), k) for (k, v) in get(prj, "deps", Dict{String,Any}())]
    weakdeps = [Base.PkgId(Base.UUID(v), k) for (k, v) in get(prj, "weakdeps", Dict{String,Any}())]

    marker = "<_START_MARKER_>"
    code = """
    import Pkg
    Pkg.activate("$(root_project_path)")
    Pkg.develop(; path="$(joinpath(@__DIR__, ".."))")
    Pkg.add("Test")
    Pkg.add("TestReports")
    Pkg.instantiate()

    using Test
    using TestReports

    ts = @testset ReportingTestSet "Example: $(root_project_path)" begin
        include("$(joinpath(root_project_path, "main.jl"))")
    end

    outputfilename = "$(joinpath(root_project_path, "report.xml"))"
    open(outputfilename, "w") do fh
        print(fh, report(ts))
    end
    println("Wrote report to \$outputfilename")

    print("$marker")
    for pkg in keys(Base.loaded_modules)
        pkg.uuid === nothing || println(pkg.uuid)
    end
    exit(any_problems(ts))
    """

    exec = Base.julia_cmd()
    cmd = `$exec --startup-file=no --color=no -e $code`
    buf = IOBuffer()
    # cmd = `julia -e "println(93284); exit(1)"`
    cmd = pipeline(cmd, stdout=buf, stderr=buf)
    @test success(cmd)
    output = String(take!(buf))

    pos = findlast(marker, output)
    @assert !isnothing(pos)
    output = output[pos.stop+1:end]
    loaded_uuids = map(Base.UUID, eachline(IOBuffer(output)))

    return Aqua.find_stale_deps_2(;
        deps = deps,
        weakdeps = weakdeps,
        loaded_uuids = loaded_uuids,
        ignore = ignore,
    )
end


ts = @testset ReportingTestSet "" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(Ensembles; ambiguities=false)
        Aqua.test_ambiguities(Ensembles)
    end

    # Set metadata for doctests.
    DocMeta.setdocmeta!(Ensembles, :DocTestSetup, :(using Ensembles, Test); recursive=true)
    if Ensembles.HAS_NATIVE_EXTENSIONS
        Ensembles.install(:Lorenz63)
        using Lorenz63
        DocMeta.setdocmeta!(
            Ensembles.get_extension(Ensembles, :Lorenz63Ext),
            :DocTestSetup,
            :(using Ensembles, Test);
            recursive=true,
        )

        # Ensembles.install(:Lorenz96)
        # using Lorenz96
        # DocMeta.setdocmeta!(
        #     Ensembles.get_extension(Ensembles, :Lorenz96Ext),
        #     :DocTestSetup,
        #     :(using Ensembles, Test);
        #     recursive=true,
        # )
    end

    doctest(Ensembles; manual=true)
    if Ensembles.HAS_NATIVE_EXTENSIONS
        doctest(Ensembles.get_extension(Ensembles, :Lorenz63Ext); manual=true)
        # doctest(Ensembles.get_extension(Ensembles, :Lorenz96Ext); manual=true)
    end

    # Run examples.
    examples_dir = joinpath(@__DIR__, "..", "examples")
    for example in readdir(examples_dir)
        example_path = joinpath(examples_dir, example)
        @show example_path
        @testset "Example: $(example)" begin
            stale_deps = run_and_find_stale_deps(example_path)
            @test isempty(stale_deps)

            report_path = joinpath(example_path, "report.xml")
            @test isfile(report_path)
        end
    end
end

outputfilename = joinpath(@__DIR__, "..", "report.xml")
open(outputfilename, "w") do fh
    print(fh, report(ts))
end
exit(any_problems(ts))
