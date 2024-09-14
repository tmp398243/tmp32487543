function get_enkf_filter(params)
    obs_std = params["observation_noise_stddev"]
    noise_type = params["observation_noise_type"]
    n = get(params, "assimilation_type", "monolithic") == "monolithic" ? 3 : 1
    if noise_type == "diagonal"
        R = Diagonal(fill(Float64(obs_std)^2, n))
    else
        throw(ArgumentError("Unknown observation noise type: $noise_type"))
    end
    filter = EnKF(R; params)
    return filter
end
