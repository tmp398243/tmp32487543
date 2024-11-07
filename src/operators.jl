export AbstractOperator, AbstractNoisyOperator
export apply_operator, apply_operator!
export get_state_keys
export split_clean_noisy, xor_seed!

abstract type AbstractOperator end
abstract type AbstractNoisyOperator <: AbstractOperator end

function (M::AbstractOperator)(
    ensemble::T, args...; inplace=false
) where {T<:AbstractEnsemble}
    if inplace
        return apply_operator!(M, ensemble, args...)
    end
    return apply_operator(M, ensemble, args...)
end

function apply_operator(
    M::AbstractOperator, ensemble::T, args...
) where {T<:AbstractEnsemble}
    members = M.(get_ensemble_members(ensemble), args...)
    return T(ensemble, members)
end

function apply_operator!(
    M::AbstractOperator, ensemble::T, args...
) where {T<:AbstractEnsemble}
    # Note: does not change the state keys.
    for em in get_ensemble_members(ensemble)
        merge!(em, M(em, args...))
    end
    return ensemble
end

function get_state_keys end

function xor_seed!(M::T, seed_mod::UInt) where {T<:AbstractNoisyOperator}
    return error("Please implement this for type $T")
end

split_clean_noisy(M::AbstractOperator, ensemble_obs::AbstractEnsemble) = ensemble_obs

function split_clean_noisy(M::AbstractNoisyOperator, ensemble_obs::AbstractEnsemble)
    N = get_ensemble_size(ensemble_obs)
    members_clean = Vector{eltype(ensemble_obs.members)}(undef, N)
    members_noisy = Vector{eltype(ensemble_obs.members)}(undef, N)
    for i in 1:N
        members_clean[i], members_noisy[i] = split_clean_noisy(M, ensemble_obs.members[i])
    end
    ensemble_clean = Ensemble(ensemble_obs, members_clean)
    ensemble_noisy = Ensemble(ensemble_obs, members_noisy)
    return ensemble_clean, ensemble_noisy
end

function split_clean_noisy(M::T, member) where {T<:AbstractNoisyOperator}
    return error("Please implement this for type $T")
end
