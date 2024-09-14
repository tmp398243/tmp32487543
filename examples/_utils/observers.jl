
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
