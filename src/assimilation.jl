
export assimilate_data

"""
    assimilate_data(filter, prior_state, [prior_obs_clean,] prior_obs, y_obs, log_data=nothing)

Return an approximation for the posterior state obtained from assimilating observation
`y_obs` based on the given prior state and prior observation.

If `log_data` is a dictionary, `assimilate_data` may log information to it.
"""
function assimilate_data end

function assimilate_data(
    filter::Nothing,
    prior_state::AbstractEnsemble,
    prior_obs::Union{AbstractEnsemble,Nothing},
    y_obs,
    log_data=nothing,
)
    return assimilate_data(filter, prior_state, prior_obs, prior_obs, y_obs, log_data)
end

"""
Return `prior_state` without modification.

This does not require observations.

# Example

Simple example showing that the prior is unchanged.

```jldoctest EnsembleDocTest
julia> members = [Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]
2-element Vector{Dict{Symbol, Any}}:
 Dict(:state => [0.7], :i => 1)
 Dict(:state => [0.5], :i => 2)

julia> prior = Ensemble(members, [:state]);

julia> posterior1 = assimilate_data(nothing, prior, nothing, nothing, members[1]);

julia> posterior2 = assimilate_data(nothing, prior, nothing, nothing, members[2]);

julia> @test prior.members == posterior1.members;

julia> @test prior.members == posterior2.members;

```
"""
function assimilate_data(
    filter::Nothing,
    prior_state::AbstractEnsemble,
    prior_obs_clean::Union{AbstractEnsemble,Nothing},
    prior_obs_noisy::Union{AbstractEnsemble,Nothing},
    y_obs,
    log_data=nothing,
)
    return prior_state
end
