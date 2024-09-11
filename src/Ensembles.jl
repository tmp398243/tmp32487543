@doc raw"""
    Ensembles

Provides an interface for applying operators to groups of similar objects.

# Extended Description

A standard model for a time-dependent system with an unknown ``x^k`` at time step ``k`` is
```math
\begin{aligned}
x^k &= f(x^{k-1}), \\
y^k &= h(x^k),
\end{aligned}
```
where ``f`` transitions the state to a new time and ``h`` create an observation ``y``.

Ensemble-based methods solve the problem of estimating the state based on observed data by
simulating multiple guesses for ``x`` and updating them to reflect the observed data.

For an ensemble ``X = \{x_1, \ldots, x_N\}`` with ``N`` members, there are three main
computational steps,

```math
\begin{aligned}
X^k &= \{f(x^{k-1}_1), \ldots, f(x^{k-1}_N) \},\\
Y^k &= \{h(x^k_1), \ldots, h(x^k_N) \}, \\
X^k_{new} &= \text{assimilate}(X^k, Y^k, y^*_0).
\end{aligned}
```

Computing ``X^k`` from ``X^{k-1}`` and computing ``Y^k`` from ``X^k`` can trivially be
decomposed into ``N`` independent computations, making parallelization trivial. The
`assimilate` step uses all the ensemble members and can be one of many algorithms.

This package provides an interface for working with this problem.

The two features of this package are:

1. Support trivially parallelizing operators that apply to each ensemble member independently.
2. Provide a common interface for ensemble-based data assimilation algorithms.

Once the operators ``f`` and ``h`` have been implemented for a single ensemble member, any
ensemble-based data assimilation algorithm can be applied to the problem and easily compared
with another.
"""
module Ensembles
include("ensemble.jl")
include("operators.jl")
include("parallel.jl")
include("parallel_file.jl")
include("parallel_operators.jl")
include("noisy_observer.jl")

using PackageExtensionCompat
function __init__()
    @require_extensions
end

export HAS_NATIVE_EXTENSIONS
HAS_NATIVE_EXTENSIONS = PackageExtensionCompat.HAS_NATIVE_EXTENSIONS

if HAS_NATIVE_EXTENSIONS
    get_extension = Base.get_extension
else
    get_extension(mod, sym) = getfield(mod, sym)
end

import Pkg
_dependencies = Dict{Symbol, Any}()
_dependencies[:Lorenz63] = () -> Pkg.add(url = "https://github.com/milankl/Lorenz63.jl#15220a7")

function install(pkg::Symbol)
    if ! (pkg in keys(_dependencies))
        error("Unknown package: $pkg")
    end
    _dependencies[pkg]()
end

end # module
