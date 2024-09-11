module Lorenz63Ext

export Lorenz63Model

import Ensembles: AbstractOperator, get_state_keys
using Lorenz63: L63

struct Lorenz63Model <: AbstractOperator
    kwargs
end

function Lorenz63Model(; params)
    kwargs = (;
        σ=Float64(params["transition"]["sigma"]),
        ρ=Float64(params["transition"]["rho"]),
        β=Float64(params["transition"]["beta"]),
        s=Float64(params["transition"]["scaling"]),
        Δt=Float64(params["transition"]["ministep_dt"]),
        N=params["transition"]["ministep_nt"],
    )
    return Lorenz63Model(kwargs)
end
get_state_keys(M::Lorenz63Model) = [:state]

function (M::Lorenz63Model)(member::Dict, args...; kwargs...)
    return Dict{Symbol,Any}(:state => M(member[:state], args...; kwargs...))
end
function (M::Lorenz63Model)(state::AbstractArray, t0, t; kwargs...)
    Δt = t - t0
    if Δt == 0
        return state
    end
    ministeps = ceil(Int, Δt / M.kwargs.Δt)
    mini_Δt = Δt / ministeps
    states = L63(; M.kwargs..., kwargs..., Δt=mini_Δt, N=ministeps, xyz=state)
    return states[:, end]
end

end
