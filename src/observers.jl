export KeyObserver, IndexObserver

struct KeyObserver <: AbstractOperator
    state_keys::Any
end
get_state_keys(M::KeyObserver) = M.state_keys

function (M::KeyObserver)(member::Dict{Symbol,Any})
    obs = typeof(member)()
    for key in get_state_keys(M)
        obs[key] = deepcopy(member[key])
    end
    return obs
end

struct IndexObserver <: AbstractOperator
    op
    i
end

function (M::IndexObserver)(member::Dict{Symbol,Any})
    em = M.op(member)
    for key in get_state_keys(M.op)
        em[key] = em[key][M.i]
    end
    return em
end
