
using Pkg: Pkg
_dependencies = Dict{Symbol,Any}()
_dependencies[:Lorenz63] =
    () -> Pkg.add(; url="https://github.com/milankl/Lorenz63.jl#15220a7")
_dependencies[:EnsembleKalmanFilters] =
    () -> Pkg.add(; url="https://github.com/DataAssimilation/EnsembleKalmanFilters.jl")
_dependencies[:NormalizingFlowFilters] =
    () -> Pkg.add(; url="https://github.com/DataAssimilation/NormalizingFlowFilters.jl")

"""
    install(pkg::Symbol)

Install unregistered package that is useful with the Ensembles package.
"""
function install(pkg::Symbol)
    if !(pkg in keys(_dependencies))
        error("Unknown package: $pkg")
    end
    return _dependencies[pkg]()
end
