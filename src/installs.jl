
using Pkg: Pkg
_dependencies = Dict{Symbol,Any}()
_dependencies[:Lorenz63] =
    () -> Pkg.add(; url="https://github.com/milankl/Lorenz63.jl#15220a7")
_dependencies[:EnsembleKalmanFilters] =
    () -> Pkg.add(; url="https://github.com/tmp398243/tmp45742")
_dependencies[:NormalizingFlowFilters] =
    () -> begin
        # Need the latest version of InvertibleNetworks for the odd input size fix.
        Pkg.add(; url="https://github.com/tmp398243/tmp337502")
        Pkg.add(; url="https://github.com/slimgroup/InvertibleNetworks.jl/")
    end

function install(pkg::Symbol)
    if !(pkg in keys(_dependencies))
        error("Unknown package: $pkg")
    end
    return _dependencies[pkg]()
end
