module StatisticsExt

using Ensembles: Ensemble
using Statistics: Statistics, mean, var, std

function Statistics.mean(
    ensemble::Ensemble{K,V}; state_keys=ensemble.state_keys
) where {K,V}
    m = Dict{K,V}()
    for key in state_keys
        m[key] = mean(em[key] for em in ensemble.members)
    end
    return m
end

function Statistics.var(ensemble::Ensemble{K,V}; state_keys=ensemble.state_keys) where {K,V}
    m = Dict{K,V}()
    for key in state_keys
        m[key] = var([em[key] for em in ensemble.members])
    end
    return m
end

function Statistics.std(ensemble::Ensemble{K,V}; state_keys=ensemble.state_keys) where {K,V}
    m = Dict{K,V}()
    for key in state_keys
        m[key] = std([em[key] for em in ensemble.members])
    end
    return m
end

end
