function rmse(ensemble, y_true)
    return sqrt(mean((ensemble .- y_true) .^ 2))
end
