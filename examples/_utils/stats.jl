function rmse(ensemble, y_true)
    sqrt(mean((ensemble .- y_true).^2))
end

function (@__MODULE__).mean(ensemble::Ensemble{K, V}) where {K, V}
    m = Dict{K, V}()
    for key in ensemble.state_keys
        m[key] = mean(em[key] for em in ensemble.members)
    end
    return m
end

function (@__MODULE__).var(ensemble::Ensemble{K, V}) where {K, V}
    m = Dict{K, V}()
    for key in ensemble.state_keys
        m[key] = var([em[key] for em in ensemble.members])
    end
    return m
end
