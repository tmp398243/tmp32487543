using JLD2: jldsave, load

export AbstractEnsemble
export Ensemble

export save_ensemble_members, load_ensemble_members
export save_ensemble, load_ensemble, move_ensemble
export get_member_vector, get_member_dict!
export get_ensemble_matrix, get_ensemble_dicts
export get_ensemble_members, get_ensemble_size

"Represents a collection of model states."
abstract type AbstractEnsemble end

"""
    Ensemble(members, state_keys; <keyword arguments>)
    Ensemble(members; <keyword arguments>)
    Ensemble(member_type, state_keys; <keyword arguments>)

AbstractEnsemble implemented with a Vector of Dicts.

# Arguments

- `members::Vector{Dict}`: the model states.
- `state_keys::Vector{Dict}`: the keys used to index the model states for conversion to an array.
    Other keys are ignored during computations. If unspecified, the sorted keys of the first
    ensemble member are used.
- `monolithic_storage::Bool = true`: whether to store the ensemble in a single file when saved.
    - `true` indicates the ensemble will be saved in a single file.
    - `false` indicates each ensemble member will be saved in a separate file.

# Examples

Specify both the members and the state keys.

```jldoctest EnsembleDocTest
julia> members = [Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]
2-element Vector{Dict{Symbol, Any}}:
 Dict(:state => [0.7], :i => 1)
 Dict(:state => [0.5], :i => 2)

julia> ensemble = Ensemble(members, [:state]);

julia> @test ensemble.members == members;

julia> @test ensemble.state_keys == [:state];

```

Create ensemble with keys taken from first ensemble member.

```jldoctest EnsembleDocTest
julia> ensemble = Ensemble(members);

julia> @test ensemble.members == members;

julia> @test ensemble.state_keys == [:i, :state];

```

Create empty ensemble with specified keys.

```jldoctest EnsembleDocTest
julia> ensemble = Ensemble(Dict{Symbol, Any}, [:state]);

julia> @test ensemble.members == [];

julia> @test ensemble.state_keys == [:state];

```

"""
struct Ensemble{K, V} <: AbstractEnsemble
    members::Vector{Dict{K, V}}
    state_keys::Vector{K}
    monolithic_storage::Bool
end

"""
    Base.show(io::IO, e::Ensemble)

Print the ensemble information on one line.

# Examples

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])], [:state]);

julia> print(e)
Ensemble(Dict{Symbol, Any}[Dict(:state => [0.7], :i => 1), Dict(:state => [0.5], :i => 2)], [:state], true)
```
"""
function Base.show(io::IO, e::Ensemble)
    print(io, "Ensemble(")
    Base.show(io, e.members)
    print(io, ", ")
    Base.show(io, e.state_keys)
    print(io, ", ")
    Base.show(io, e.monolithic_storage)
    print(io, ")")
end

"""
    Base.show(io::IO, ::MIME"text/plain", e::Ensemble)

Print the ensemble information in a human-readable multi-line form.

# Examples

```jldoctest
julia> Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])], [:state])
Ensemble{Symbol, Any}:

members =
 Dict(:state => [0.7], :i => 1)
 Dict(:state => [0.5], :i => 2)

state_keys = [:state]
monolithic_storage = true

julia> Ensemble(Dict{Symbol, Any}[], [:state])
Ensemble{Symbol, Any}:

members = []
state_keys = [:state]
monolithic_storage = true
```
"""
function Base.show(io::IO, mime::MIME"text/plain", e::Ensemble)
    Base.summary(io, e)
    println(io, ":")
    println(io)
    print(io, "members =")
    if length(e.members) == 0
        println(io, " []")
    else
        lines, columns = displaysize(io)
        io = IOContext(io,
            :typeinfo => eltype(e.members),
            :displaysize => (max(lines - 5, 1), columns)
        )
        println(io)
        Base.print_array(io, e.members)
        println(io)
        println(io)
    end
    print(io, "state_keys = ")
    Base.show(io, e.state_keys)
    println(io)
    print(io, "monolithic_storage = ")
    Base.show(io, mime, e.monolithic_storage)
end

# function Ensemble{K, V}(members::Vector{E}, state_keys::Vector{K};
#         monolithic_storage = true) where {K, V, E <: Dict{K, V}}
#     Ensemble{K, V}(members, state_keys, monolithic_storage)
# end

function Ensemble(members::Vector{E}, state_keys::Vector{K};
        monolithic_storage = true) where {K, V, E <: Dict{K, V}}
    Ensemble(members, state_keys, monolithic_storage)
end

function Ensemble(members::Vector{E}; kwargs...) where {K, V, E <: Dict{K, V}}
    Ensemble(members, (sort ∘ collect ∘ keys)(members[1]); kwargs...)
end

function Ensemble(::Type{E}, state_keys::Vector{K}; kwargs...) where {K, V, E <: Dict{K, V}}
    Ensemble(Vector{E}(), state_keys; kwargs...)
end

"""
    Ensemble(ensemble, members, state_keys)

Create a new ensemble using the given `ensemble`'s parameters, which is just `monolithic_storage` for now.

# Examples

```jldoctest
julia> ensemble = Ensemble(Dict{Symbol, Any}, [:state]; monolithic_storage = false);

julia> members = [Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])];

julia> ensemble = Ensemble(ensemble, members, [:state]);

julia> @test ensemble.members == members;

julia> @test ensemble.state_keys == [:state];

julia> @test ensemble.monolithic_storage == false;
```
"""
Ensemble(ensemble::Ensemble, members::Vector, state_keys::Vector{Symbol}) = Ensemble(
    members, state_keys; ensemble.monolithic_storage)

function Ensemble{K, V}(
        ensemble::Ensemble{K, V}, members::Vector, state_keys::Vector{Symbol}) where {K, V}
    Ensemble(
        members, state_keys; ensemble.monolithic_storage)
end

"""
    Ensemble(ensemble, members)

Create a new ensemble using the given `ensemble`'s parameters, which is just `monolithic_storage` for now.

# Examples

```jldoctest
julia> ensemble = Ensemble(Dict{Symbol, Any}, [:state]; monolithic_storage = false);

julia> members = [Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])];

julia> ensemble = Ensemble(ensemble, members);

julia> @test ensemble.members == members;

julia> @test ensemble.state_keys == [:i, :state];

julia> @test ensemble.monolithic_storage == false;
```
"""
Ensemble(ensemble::Ensemble, members::Vector) = Ensemble(
    members; ensemble.monolithic_storage)

function Ensemble{K, V}(ensemble::Ensemble{K, V}, members::Vector) where {K, V}
    Ensemble(
        members; ensemble.monolithic_storage)
end

# Loop through each constructor and create a new constructor for Ensemble{K,V}
# for m in methods(Ensemble)
#     if m.sig.parameters[1] != Type{Ensemble}
#         continue
#     end

#     # Create the new signature for Ensemble{K,V}
#     params = m.sig.parameters[2:end]
#     args_kwargs = [:($(Symbol("arg", i))::$(p)) for (i, p) in enumerate(params)]

#     call = Expr(:call, :(Ensemble{K,V}), args_kwargs...)
#     new_sig = Expr(
#         :where,
#         call,
#         :K,
#         :V
#     )

#     # Create the body of the new method
#     body = Expr(:call, :Ensemble, [Symbol("arg", i) for i in 1:length(params)]...)

#     # Create the new signature for Ensemble{K,V}
#     new_sig = Expr(
#         :where,
#         Expr(:call, :(Ensemble{K,V}), (m.sig.parameters[2:end]...)),
#         :K,
#         :V
#     )

#     # Create the body of the new method
#     body = Expr(:call, :Ensemble, (m.sig.parameters[2:end]...))

#     # Create and evaluate the new method
#     @eval $new_sig = $body
# end

"""
    merge!(e::Ensemble, e1::Ensemble)

Overwrite the first ensemble's members with corresponding values from the second ensemble.

The two ensembles must have the same size.

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]);

julia> e1 = Ensemble([Dict(:state=>[0.3], :obs=>[3.5]), Dict(:state=>[0.1], :obs=>[2.3])]);

julia> merge!(e, e1);

julia> e.members
2-element Vector{Dict{Symbol, Any}}:
 Dict(:state => [0.3], :obs => [3.5], :i => 1)
 Dict(:state => [0.1], :obs => [2.3], :i => 2)

julia> @test e.state_keys == [:i, :state];

```
See also [`merge`](@ref).
"""
Base.merge!(e::Ensemble, e1::Ensemble) = (merge!.(e.members, e1.members); e)

"""
Create a new ensemble using values from the first ensemble overwritten with values from the second ensemble.

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]);

julia> e1 = Ensemble([Dict(:state=>[0.3], :obs=>[3.5]), Dict(:state=>[0.1], :obs=>[2.3])]);

julia> e2 = merge(e, e1);

julia> e2.members
2-element Vector{Dict{Symbol, Any}}:
 Dict(:state => [0.3], :obs => [3.5], :i => 1)
 Dict(:state => [0.1], :obs => [2.3], :i => 2)

julia> @test e2.state_keys == [:i, :obs, :state];

```
See also [`merge!`](@ref).
"""
Base.merge(e::Ensemble, e1::Ensemble) = Ensemble(
    merge.(e.members, e1.members); e.monolithic_storage)

"""
    get_ensemble_size(ensemble::Ensemble)

Get the number of members in an ensemble.
"""
get_ensemble_size(ensemble::Ensemble) = length(ensemble.members)

"""
    get_ensemble_members(ensemble::Ensemble)

Get the members of an ensemble.
"""
get_ensemble_members(ensemble::Ensemble) = ensemble.members

"""
    get_member_vector(ensemble, member::Dict)

Convert an ensemble member to a Vector.

The Vector is generated by by one-dimensionalizing each value in the member
at the keys specified by `ensemble.state_keys`.

# Examples

Convert two ensemble members to vectors.

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.8])]);

julia> get_member_vector(e, e.members[1])
2-element Vector{Float64}:
 1.0
 0.7

julia> get_member_vector(e, e.members[2])
2-element Vector{Float64}:
 2.0
 0.8
```

Limit the vectorizing attributes by specifying them in the Ensemble definition.

```jldoctest
julia> member1 = Dict(:i=>1, :state=>[[0.1, 0.3], [0.2, 0.4]])
Dict{Symbol, Any} with 2 entries:
  :state => [[0.1, 0.3], [0.2, 0.4]]
  :i     => 1

julia> member2 = Dict(:i=>2, :state=>[[0.2, 0.6], [0.4, 0.8]])
Dict{Symbol, Any} with 2 entries:
  :state => [[0.2, 0.6], [0.4, 0.8]]
  :i     => 2

julia> e = Ensemble([member1, member2], [:state]);

julia> get_member_vector(e, e.members[1])
4-element Vector{Float64}:
 0.1
 0.3
 0.2
 0.4

julia> get_member_vector(e, e.members[2])
4-element Vector{Float64}:
 0.2
 0.6
 0.4
 0.8
```

See also [`get_member_dict!`](@ref), [`get_ensemble_matrix`](@ref).
"""
function get_member_vector(ensemble::Ensemble, member::Dict)
    get_member_vector(ensemble.state_keys, member)
end

function get_member_vector(state_keys::Vector, member::Dict)
    reduce(vcat, _get_vector(member[key]) for key in state_keys)
end

"Helper function for converting variety of types to a vector"
function _get_vector end
_get_vector(a::Dict) = reduce(vcat, _get_vector(a[key]) for key in keys(a))
_get_vector(a::AbstractArray) = vec(a)
_get_vector(a::AbstractArray{<:AbstractArray}) = vcat(_get_vector.(a)...)
_get_vector(a::Number) = [a]

"""
    get_member_dict!(ensemble, member::Dict, data::Vector)

Write a data Vector to an ensemble member Dict.

This is the inverse of [`get_member_vector`](@ref).

# Examples

Write data to a vector.

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7])]);

julia> e.members[1];

julia> data = [5, -0.4];

julia> get_member_dict!(e, e.members[1], data)
Dict{Symbol, Any} with 2 entries:
  :state => [-0.4]
  :i     => 5.0

julia> @test get_member_vector(e, e.members[1]) == data;
```

Limit the vectorizing attributes by specifying them in the Ensemble definition.

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[[0.1, 0.3], [0.2, 0.4]])], [:state]);

julia> data = [-0.9, -0.3, -0.4, -0.7];

julia> get_member_dict!(e, e.members[1], data)
Dict{Symbol, Any} with 2 entries:
  :state => [[-0.9, -0.3], [-0.4, -0.7]]
  :i     => 1

julia> @test get_member_vector(e, e.members[1]) == data;
```

See also [`get_member_vector`](@ref), [`get_ensemble_matrix`](@ref).
"""
function get_member_dict!(ensemble::Ensemble, member::Dict, data::AbstractVector)
    idx = 1
    n = length(data)
    for key in ensemble.state_keys
        member[key], idx = _set_vector!(member[key], view(data, idx:n))
    end
    if idx < n
        error("Member has $idx values but tried to assign vector of length $n > $idx")
    end
    return member
end

"Helper function for assigning a vector to a variety of types."
function _set_vector! end
_set_vector!(a, v::AbstractVector) = _set_vector!(a, v, 1)
_set_vector!(x::Number, v::AbstractVector, idx::Int) = v[idx], idx + 1

function _set_vector!(x::AbstractArray, v::AbstractVector, idx::Int)
    x .= v[idx:(idx + length(x) - 1)]
    idx += length(x)
    return x, idx
end

function _set_vector!(x::AbstractArray{<:AbstractArray}, v::AbstractVector, idx::Int)
    for j in eachindex(x)
        x[j], idx = _set_vector!(x[j], v, idx)
    end
    return x, idx
end

function _set_vector!(x::Dict, v::AbstractVector, idx::Int)
    idx = 1
    n = length(v)
    for k in keys(x)
        x[k], idx = _set_vector!(x[k], view(v, idx:n))
    end
    return x, idx
end

"""
    get_ensemble_matrix(ensemble)

Convert an ensemble with N members to a matrix with N columns.

Each ensemble member must have the same length when vectorized with [`get_member_vector`](@ref).

# Examples

Convert an ensemble to a matrix.

```jldoctest
julia> members = [
           Dict(:i=>1, :state=>[0.1]),
           Dict(:i=>2, :state=>[2.6]),
       ];

julia> e = Ensemble(members);

julia> get_ensemble_matrix(e)
2×2 Matrix{Float64}:
 1.0  2.0
 0.1  2.6
```

Convert an ensemble to a matrix based on the ensemble state keys.

```jldoctest
julia> members = [
           Dict(:i=>1, :state=>[[0.1, 0.3], [0.2, 0.4]]),
           Dict(:i=>2, :state=>[[-1.6, 6.4], [2.6, 5.9]]),
       ];

julia> e = Ensemble(members, [:state]);

julia> get_ensemble_matrix(e)
4×2 Matrix{Float64}:
 0.1  -1.6
 0.3   6.4
 0.2   2.6
 0.4   5.9
```

See also [`get_member_vector`](@ref), [`get_ensemble_dicts`](@ref).
"""
function get_ensemble_matrix(ensemble::Ensemble)
    get_ensemble_matrix(ensemble.state_keys, ensemble.members)
end

function get_ensemble_matrix(state_keys::Vector, members)
    return reduce(
        hcat,
        get_member_vector(state_keys, member)
        for member in members
    )
end

"""
    get_ensemble_dicts(ensemble, matrix)

Convert the matrix form of an ensemble to the Dict form.

# Examples

```jldoctest
julia> data = [
           -0.9; -0.3; -0.4; -0.7 ;;
            5.9;  5.3;  5.4;  5.7 ;;
       ];

julia> members = [
           Dict(:i=>1, :state=>[[0.1, 0.3], [0.2, 0.4]]),
           Dict(:i=>2, :state=>[[-1.6, 6.4], [2.6, 5.9]]),
       ];

julia> e = Ensemble(members, [:state]);

julia> members2 = get_ensemble_dicts(e, data);

julia> @test get_member_vector(e, members2[1]) == data[:,1];

julia> @test get_member_vector(e, members2[2]) == data[:,2];
```

See also [`get_member_dict!`](@ref), [`get_ensemble_matrix`](@ref).
"""
function get_ensemble_dicts(ensemble::Ensemble, matrix::AbstractArray{T, 2}) where {T}
    members = deepcopy(ensemble.members)
    for (i, (em, data)) in enumerate(zip(members, eachcol(matrix)))
        get_member_dict!(ensemble, em, data)
    end
    return members
end

"""
    save_ensemble_members(ensemble::Ensemble, folder_path; <keyword arguments>)

Save each member of the ensemble to separate file with path "folder_path/i.jld2" with JLD2 key "data", where `i` is
the ensemble member's index in the ensemble.

# Arguments

- `existing_member_directory`: specifies the path to an existing directory where the ensemble members are saved.
    This directory takes precedence over `ensemble.members`.
- `existing_merge::Bool`: if `true` and the existing directory is given, merge the existing directory members
    with `ensemble.members`. If `false`, `ensemble.members` are not used.

# Examples

Save an ensemble to a directory.

```jldoctest SaveEnsembleDocTest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]);

julia> d = mktempdir(".");

julia> save_ensemble_members(e, d)

julia> readdir(d)
2-element Vector{String}:
 "1.jld2"
 "2.jld2"

julia> loaded_members = load_ensemble_members(d, 2);

julia> @test e.members == loaded_members;
```

Use an existing ensemble directory instead of the in-memory ensemble members.

```jldoctest SaveEnsembleDocTest
julia> e2 = Ensemble([Dict(:i=>3, :state=>[3.1]), Dict(:i=>4, :state=>[2.7])]);

julia> d2 = mktempdir("."); rm(d2);

julia> save_ensemble_members(e2, d2; existing_member_directory=d)

julia> @test isdir(d) == false;

julia> readdir(d2)
2-element Vector{String}:
 "1.jld2"
 "2.jld2"

julia> loaded_members = load_ensemble_members(d2, 2);

julia> @test e.members == loaded_members;

julia> @test e2.members != loaded_members;
```

Merge an existing ensemble directory over the in-memory ensemble members.

```jldoctest SaveEnsembleDocTest
julia> e3 = Ensemble([Dict(:i=>3, :obs=>[55.5]), Dict(:i=>4, :obs=>[34.3])]);

julia> d3 = mktempdir("."); rm(d3);

julia> save_ensemble_members(e3, d3; existing_member_directory=d2, existing_merge=true)

julia> @test isdir(d2) == false;

julia> readdir(d3)
2-element Vector{String}:
 "1.jld2"
 "2.jld2"

julia> loaded_members = load_ensemble_members(d3, 2);

julia> @test merge.(e.members, e3.members) == loaded_members;
```

See also [`load_ensemble_members`](@ref), [`load_ensemble`](@ref), [save_ensemble`](@ref),
and [`move_ensemble`](@ref).
"""
function save_ensemble_members(ensemble::Ensemble, folder_path;
        existing_member_directory = nothing, existing_merge = false)
    if !isnothing(existing_member_directory)
        if existing_merge
            mkpath(folder_path)
            for (i, em) in enumerate(ensemble.members)
                em_file_name_new = joinpath(existing_member_directory, "$i.jld2")
                em_new = load(em_file_name_new, "data")
                merge!(em, em_new)

                em_file_name = joinpath(folder_path, "$i.jld2")
                jldsave(em_file_name; data = em)
                rm(em_file_name_new)
            end
            try
                rm(existing_member_directory)
            catch e
                @error "Error removing member directory $(existing_member_directory): $(e.msg)"
            end
        else
            mv(existing_member_directory, folder_path)
        end
    else
        mkpath(folder_path)
        for (i, em) in enumerate(ensemble.members)
            em_file_name = joinpath(folder_path, "$i.jld2")
            jldsave(em_file_name; data = em)
        end
    end
    return
end

"""
    load_ensemble_members(folder_path, N)

Load the `N` ensemble members from the specified `folder_path`; uses the pattern "folder_path/i.jld2"
for the i-th ensemble member.

See [`save_ensemble_members`](@ref) for examples.

See also [`load_ensemble`](@ref), [`save_ensemble`](@ref), and [`move_ensemble`](@ref).
"""
function load_ensemble_members(folder_path, N)
    members = nothing
    for i in 1:N
        em_file_name = joinpath(folder_path, "$i.jld2")
        em = load(em_file_name, "data")
        if i == 1
            members = Vector{typeof(em)}(undef, N)
        end
        members[i] = em
    end
    return members
end

"""
    save_ensemble(ensemble, stem; <keyword arguments>)

Save the given ensemble at the given file stem.

For monolithic storage, the whole ensemble is saved in "stem.jld2". Otherwise, the members are
saved each to their own file, with any remaining ensemble parameters saved to "stem.jld2".

# Arguments

- `existing_member_directory`: specifies the path to an existing directory where the ensemble members are saved.
    This directory takes precedence over `ensemble.members`.
- `existing_merge::Bool`: if `true` and the existing directory is given, merge the existing directory members
    with `ensemble.members`. If `false`, `ensemble.members` are not used.
- `reset_state_keys::Bool`: if `true` and the existing directory is given and `existing_merge` is `true`, then
    re-initialize the ensemble's `state_keys` based on the merged ensemble members. If `false`, the state keys
    are unchanged.

# Examples

Save an ensemble to a single file.

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]; monolithic_storage = true);

julia> d = mktempdir(".");

julia> stem = joinpath(d, "e");

julia> save_ensemble(e, stem)

julia> readdir(d)
1-element Vector{String}:
 "e.jld2"

julia> e2 = load_ensemble(stem);

julia> @test e2.members == e.members;

julia> @test e2.state_keys == e.state_keys;

julia> @test e2.monolithic_storage == e.monolithic_storage;
```

Save an ensemble across multiple files.

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]; monolithic_storage = false);

julia> d = mktempdir(".");

julia> stem = joinpath(d, "e");

julia> save_ensemble(e, stem)

julia> readdir(d)
2-element Vector{String}:
 "e.jld2"
 "e_ensemble"

julia> readdir(joinpath(d, "e_ensemble"))
2-element Vector{String}:
 "1.jld2"
 "2.jld2"

julia> e2 = load_ensemble(stem);

julia> @test e2.members == e.members;

julia> @test e2.state_keys == e.state_keys;

julia> @test e2.monolithic_storage == e.monolithic_storage;
```

Save but replace the ensemble members with an existing ensemble stored across files.

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]; monolithic_storage = false);

julia> d = mktempdir(".");

julia> stem = joinpath(d, "e");

julia> ensemble_dir = joinpath(d, "e_ensemble");

julia> save_ensemble(e, stem)

julia> e2 = Ensemble([Dict(:i=>3, :obs=>[55.5]), Dict(:i=>4, :obs=>[34.3])]; monolithic_storage = true);

julia> d2 = mktempdir(".");

julia> stem2 = joinpath(d2, "e");

julia> save_ensemble(e2, stem2; existing_member_directory=ensemble_dir)

julia> @test isdir(ensemble_dir) == false;

julia> e3 = load_ensemble(stem2);

julia> @test e3.members == e.members;

julia> @test e3.state_keys == e2.state_keys;

julia> @test e3.monolithic_storage == e2.monolithic_storage;
```

Save the ensemble but *merge* the ensemble members with an existing ensemble stored across files.

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]; monolithic_storage = false);

julia> d = mktempdir(".");

julia> stem = joinpath(d, "e");

julia> ensemble_dir = joinpath(d, "e_ensemble");

julia> save_ensemble(e, stem)

julia> e2 = Ensemble([Dict(:i=>3, :obs=>[55.5]), Dict(:i=>4, :obs=>[34.3])]; monolithic_storage = true);

julia> d2 = mktempdir(".");

julia> stem2 = joinpath(d2, "e");

julia> save_ensemble(e2, stem2; existing_member_directory=ensemble_dir, existing_merge=true)

julia> @test isdir(ensemble_dir) == false;

julia> e3 = load_ensemble(stem2);

julia> @test e3.members == merge.(e.members, e2.members);

julia> @test e3.state_keys == [:i, :obs];

julia> @test e3.monolithic_storage == e2.monolithic_storage;
```

Reset the keys after merging.

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]; monolithic_storage = false);

julia> d = mktempdir(".");

julia> stem = joinpath(d, "e");

julia> ensemble_dir = joinpath(d, "e_ensemble");

julia> save_ensemble(e, stem)

julia> e2 = Ensemble([Dict(:i=>3, :obs=>[55.5]), Dict(:i=>4, :obs=>[34.3])]; monolithic_storage = true);

julia> d2 = mktempdir(".");

julia> stem2 = joinpath(d2, "e");

julia> save_ensemble(e2, stem2; existing_member_directory=ensemble_dir, existing_merge=true, reset_state_keys=true)

julia> @test isdir(ensemble_dir) == false;

julia> e3 = load_ensemble(stem2);

julia> @test e3.members == merge.(e.members, e2.members);

julia> @test e3.state_keys == [:i, :obs, :state];

julia> @test e3.monolithic_storage == e2.monolithic_storage;
```

See also [`save_ensemble_members`](@ref), [`load_ensemble_members`](@ref), [`load_ensemble`](@ref),
and [`move_ensemble`](@ref).
"""
function save_ensemble(ensemble::Ensemble, stem; existing_member_directory = nothing,
        existing_merge = false, reset_state_keys = false)
    file_name = "$stem.jld2"
    if isfile(file_name)
        stem_new = "$(stem)-1"
        @error("$file_name already exists. Moving existing version to $(stem_new)")
        move_ensemble(stem, stem_new)
    end
    if ensemble.monolithic_storage
        members = ensemble.members
        if !isnothing(existing_member_directory)
            members = load_ensemble_members(
                existing_member_directory, get_ensemble_size(ensemble))
            if existing_merge
                for (em, em_new) in zip(ensemble.members, members)
                    merge!(em, em_new)
                end
                members = ensemble.members
            end
            if reset_state_keys
                ensemble = Ensemble(ensemble, members)
            end
        end
        data = (;
            members = members,
            state_keys = ensemble.state_keys,
            monolithic_storage = ensemble.monolithic_storage,
            version = "1.0.1"
        )
        jldsave(file_name; data...)
        if !isnothing(existing_member_directory)
            for i in 1:get_ensemble_size(ensemble)
                em_file_name = joinpath(existing_member_directory, "$i.jld2")
                rm(em_file_name)
            end
            try
                rm(existing_member_directory)
            catch e
                @error "Error removing member directory $(existing_member_directory): $(e.msg)"
            end
        end
        return
    end
    save_ensemble_members(
        ensemble, "$(stem)_ensemble"; existing_member_directory, existing_merge)
    data = (;
        state_keys = ensemble.state_keys,
        monolithic_storage = ensemble.monolithic_storage,
        version = "1.0.1"
    )
    jldsave(file_name; data...)
end

"""
    load_ensemble(stem)

Loads the ensemble saved at the given stem.

See [`save_ensemble_members`](@ref) for examples.

See also [`load_ensemble_members`](@ref), [`load_ensemble`](@ref), [`save_ensemble`](@ref),
and [`move_ensemble`](@ref).
"""
function load_ensemble(stem)
    file_name = "$stem.jld2"
    version = load(file_name, "version")
    if version == "1.0.0"
        members, state_keys = load(file_name, "members", "state_keys")
        ensemble = Ensemble(members, state_keys, true)
        return ensemble
    end
    if version == "1.0.1"
        monolithic_storage = load(file_name, "monolithic_storage")
        if monolithic_storage
            members, state_keys = load(file_name, "members", "state_keys")
        else
            state_keys = load(file_name, "state_keys")
            folder_path = "$(stem)_ensemble"
            files = filter(f -> endswith(f, ".jld2"), readdir(folder_path))
            numbers = [parse(Int, splitext(f)[1])
                       for f in files if all(isdigit, splitext(f)[1])]
            N = isempty(numbers) ? 0 : maximum(numbers)
            members = load_ensemble_members(folder_path, N)
        end
        ensemble = Ensemble(members, state_keys; monolithic_storage)
        return ensemble
    end
    error("Invalid ensemble version: $version")
end

"""
    move_ensemble(stem, stem_new)

Moves an ensembled stored at `stem` to `stem_new`.

If an ensemble is already saved at `stem_new`, that ensemble is moved to `stem_new-1`.

# Examples

Create and move an ensemble.

```jldoctest
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]; monolithic_storage = false);

julia> d = mktempdir(".");

julia> stem = joinpath(d, "e");

julia> save_ensemble(e, stem)

julia> stem_new = joinpath(d, "f");

julia> move_ensemble(stem, stem_new)

julia> e2 = load_ensemble(stem_new);

julia> @test e2.members == e.members;

julia> @test e2.state_keys == e.state_keys;

julia> @test e2.monolithic_storage == e.monolithic_storage;
```

Move an ensemble on top of an existing one.

```jldoctest; filter = [r"\\./jl_[^/]*/" => "./", r"@ Ensembles.*\$"]
julia> e = Ensemble([Dict(:i=>1, :state=>[0.7]), Dict(:i=>2, :state=>[0.5])]; monolithic_storage = false);

julia> d = mktempdir(".");

julia> stem = joinpath(d, "e");

julia> save_ensemble(e, stem)

julia> e2 = Ensemble([Dict(:i=>3, :obs=>[55.5]), Dict(:i=>4, :obs=>[34.3])]; monolithic_storage = true);

julia> d2 = mktempdir(".");

julia> stem2 = joinpath(d2, "e");

julia> save_ensemble(e2, stem2)

julia> move_ensemble(stem, stem2)
┌ Error: ./jl_SNKG0N/e.jld2 already exists. Moving existing version to ./jl_SNKG0N/e-1
└ @ Ensembles ~/a/curr_research/JutulJUDIFilter/Ensembles.jl/src/Ensembles.jl:527

julia> e_a = load_ensemble(stem2);

julia> @test e_a.members == e.members;

julia> @test e_a.state_keys == e.state_keys;

julia> @test e_a.monolithic_storage == e.monolithic_storage;

julia> e2_a = load_ensemble("\$stem2-1");

julia> @test e2_a.members == e2.members;

julia> @test e2_a.state_keys == e2.state_keys;

julia> @test e2_a.monolithic_storage == e2.monolithic_storage;
```

See also [`save_ensemble_members`](@ref), [`load_ensemble_members`](@ref), [`load_ensemble`](@ref),
and [`save_ensemble`](@ref).
"""
function move_ensemble(stem, stem_new)
    file_name_new = "$stem_new.jld2"
    if isfile(file_name_new)
        stem_new_new = "$(stem_new)-1"
        @error("$file_name_new already exists. Moving existing version to $(stem_new_new)")
        move_ensemble(stem_new, stem_new_new)
    end
    file_name = "$stem.jld2"
    mv(file_name, file_name_new)

    version = load(file_name_new, "version")
    if version == "1.0.0"
        return
    end
    if version == "1.0.1"
        monolithic_storage = load(file_name_new, "monolithic_storage")
        if !monolithic_storage
            folder_path = "$(stem)_ensemble"
            folder_path_new = "$(stem_new)_ensemble"
            mv(folder_path, folder_path_new)
        end
        return
    end
    error("Invalid ensemble version: $version")
end
