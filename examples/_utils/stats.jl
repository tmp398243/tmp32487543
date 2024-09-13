function rmse(ensemble, y_true)
    sqrt(mean((ensemble .- y_true).^2))
end
