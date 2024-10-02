
using Pkg: Pkg
_dependencies = Dict{Symbol,Any}()
_dependencies[:Lorenz63] =
    () -> Pkg.add(; url="https://github.com/milankl/Lorenz63.jl#15220a7")
_dependencies[:EnsembleKalmanFilters] =
    () -> Pkg.add(; url="https://github.com/tmp398243/tmp45742")
_dependencies[:NormalizingFlowFilters] =
    () -> Pkg.add(; url="https://github.com/tmp398243/tmp337502")

function install(pkg::Symbol)
    if !(pkg in keys(_dependencies))
        error("Unknown package: $pkg")
    end
    return _dependencies[pkg]()
end
