export KeyObserver, IndexObserver

"""
    KeyObserver(state_keys)

Create an operator that copies the given state keys from each ensemble member.

# Examples

```jldoctest
julia> member = Dict(:i=>1, :state=>[0.7, 0.2]);

julia> M = KeyObserver([:state]);

julia> obs = M(member);

julia> @test obs == Dict(:state => member[:state]);

```
"""
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

"""
    IndexObserver(op, i)

Create an operator that applies `op` and then extracts element `i` from each state key of `op`.

# Examples

```jldoctest
julia> member = Dict(:i=>1, :state=>[0.7, 0.2]);

julia> M = IndexObserver(KeyObserver([:state]), 2);

julia> obs = M(member);

julia> @test obs == Dict(:state => member[:state][2]);

```
"""
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
