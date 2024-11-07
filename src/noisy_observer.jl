
export NoisyObserver
using Random: Random

struct NoisyObserver{O<:AbstractOperator} <: AbstractNoisyOperator
    op::O
    state_keys::Vector{Symbol}
    noise_scale::Any
    rng::Any
    seed::Any
    only_noisy::Bool
end

get_state_keys(M::NoisyObserver) = M.state_keys
get_underlying_operator(M::NoisyObserver) = M.op
xor_seed!(M::NoisyObserver, seed_mod::UInt) = Random.seed!(M.rng, xor(M.seed, seed_mod))

function NoisyObserver(op::AbstractOperator; only_noisy=nothing, params)
    noise_scale = params["observation"]["noise_scale"]
    seed = get(params["observation"], "seed", 0)
    rng = get(params["observation"], "rng", Random.MersenneTwister(seed))
    if seed == 0
        seed = Random.rand(UInt64)
    end
    Random.seed!(rng, seed)
    if isnothing(only_noisy)
        only_noisy = get(params["observation"], "only_noisy", false)
    end
    state_keys = get_state_keys(op)
    if !only_noisy
        state_keys = append!(
            [Symbol(key, :_noisy) for key in get_state_keys(op)], state_keys
        )
    end

    return NoisyObserver(op, state_keys, noise_scale, rng, seed, only_noisy)
end

NoisyObserver(state_keys; params) = NoisyObserver(KeyObserver(state_keys); params)

function (M::NoisyObserver)(member::Dict{Symbol,Any}, args...)
    member = M.op(member, args...)
    obs = typeof(member)()
    for key in get_state_keys(M.op)
        state = member[key]
        obs[key] = deepcopy(state)

        noisy_key = M.only_noisy ? key : Symbol(key, :_noisy)
        obs[noisy_key] = deepcopy(state)

        noisy = _get_vector(obs[noisy_key])
        noise = M.noise_scale .* Random.randn(M.rng, size(noisy))
        noisy .+= noise
        _set_vector!(obs[noisy_key], noisy)
    end
    return obs
end

function split_clean_noisy(M::NoisyObserver, obs::Dict{Symbol,<:Any})
    obs_clean = typeof(obs)()
    obs_noisy = typeof(obs)()
    for key in get_state_keys(M.op)
        obs_clean[key] = obs[key]
        obs_noisy[key] = obs[Symbol(key, :_noisy)]
    end
    return obs_clean, obs_noisy
end
