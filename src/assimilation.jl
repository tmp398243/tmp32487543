
export assimilate_data

function assimilate_data(
    filter::Nothing,
    prior_state::AbstractEnsemble,
    prior_obs::AbstractEnsemble,
    y_obs,
    log_data=nothing,
)
    return assimilate_data(filter, prior_state, prior_obs, prior_obs, y_obs, log_data)
end

function assimilate_data(
    filter::Nothing,
    prior_state::AbstractEnsemble,
    prior_obs_clean::AbstractEnsemble,
    prior_obs_noisy::AbstractEnsemble,
    y_obs,
    log_data=nothing,
)
    return prior_state
end
