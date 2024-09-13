module StatisticsExt

using Ensembles: Ensemble
using Statistics: mean, var

function mean(ensemble::Ensemble{K, V}) where {K, V}
    m = Dict{K, V}()
    for key in ensemble.state_keys
        m[key] = mean(em[key] for em in ensemble.members)
    end
    return m
end

function var(ensemble::Ensemble{K, V}) where {K, V}
    m = Dict{K, V}()
    for key in ensemble.state_keys
        m[key] = var([em[key] for em in ensemble.members])
    end
    return m
end

end