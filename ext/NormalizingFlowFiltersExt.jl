module NormalizingFlowFiltersExt

using Ensembles:
    Ensembles, Ensemble, get_ensemble_matrix, get_ensemble_dicts, get_member_vector
using NormalizingFlowFilters: NormalizingFlowFilters, NormalizingFlowFilter

function Ensembles.assimilate_data(
    filter::NormalizingFlowFilter,
    ensemble,
    ensemble_obs_clean,
    ensemble_obs_noisy,
    y_obs,
    log_data,
)
    X_matrix = NormalizingFlowFilters.assimilate_data(
        filter,
        Float64.(get_ensemble_matrix(ensemble)),
        Float64.(get_ensemble_matrix(ensemble_obs_clean)),
        Float64.(get_ensemble_matrix(ensemble_obs_noisy)),
        get_member_vector(ensemble_obs_clean, y_obs),
        log_data,
    )
    members = get_ensemble_dicts(ensemble, X_matrix)
    posterior = Ensemble(members, ensemble.state_keys)
    return posterior
end

end
