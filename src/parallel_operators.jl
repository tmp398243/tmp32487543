using Distributed:
    myid,
    remotecall,
    RemoteChannel,
    RemoteException,
    @everywhere,
    pmap,
    AbstractWorkerPool,
    default_worker_pool,
    @distributed,
    @sync,
    nworkers,
    workers,
    remotecall_wait
using Random: Random

export DistributedOperator

abstract type AbstractParallelOperator <: AbstractOperator end

struct DistributedOperator{T<:AbstractOperator,W<:AbstractWorkerPool,K<:AbstractDict,D} <:
       AbstractParallelOperator
    op::T
    worker_pool::W
    pmap_kwargs::K
    distributed_type::Val{D}
end

function DistributedOperator(
    op::T,
    worker_pool::W=default_worker_pool(),
    distributed_type::Val=Val(:asyncmap);
    kwargs...,
) where {T<:AbstractOperator,W<:AbstractWorkerPool}
    return DistributedOperator(op, worker_pool, kwargs, distributed_type)
end

function DistributedOperator(
    op::T, distributed_type::Val; kwargs...
) where {T<:AbstractOperator}
    return DistributedOperator(op, default_worker_pool(), kwargs, distributed_type)
end

function (M::DistributedOperator)(ensemble::E, args...) where {E<:AbstractEnsemble}
    return apply_operator(M, ensemble, args...)
end

function apply_operator(
    M::DistributedOperator{T,W,K,D}, ensemble::E, args...
) where {T,W,K,D,E<:AbstractEnsemble}
    seeds = nothing
    if T <: AbstractNoisyOperator
        if !(D in [:asyncmap])
            error("Distributed type $D does not support noisy operators")
        end
        seeds = Dict(p => Random.rand(UInt) for p in workers())
    end
    function func0(; seeds=seeds, M=M, args=args)
        @debug "Initializing process $(myid())"
        if T <: AbstractNoisyOperator
            xor_seed!(M.op, seeds[myid()])
        end

        # Define function for operating on each ensemble member.
        function func((i, em))
            @debug "  - Doing ensemble member $(i)"
            em_new = M.op(em, args...)
            return em_new
        end
        return func
    end
    members = _apply_operator(M, func0, ensemble)
    return E(ensemble, members)
end

function _apply_operator(
    M::DistributedOperator{T,W,K,:pmap}, func0, ensemble::AbstractEnsemble, args...
) where {T,W,K}
    iterator = enumerate(get_ensemble_members(ensemble))
    func = func0()
    return pmap(func, M.worker_pool, iterator; M.pmap_kwargs...)
end

function _apply_operator(
    M::DistributedOperator{T,W,K,:distributed_for}, func0, ensemble::AbstractEnsemble
) where {T,W,K}
    members = get_ensemble_members(ensemble)
    func = func0()
    if M.worker_pool != default_worker_pool()
        @warn "This may not use the right worker pool"
    end
    results = @sync @distributed (vcat) for i in 1:length(members)
        [(i, func(i, members[i]))]
    end
    sort!(results; by=first)
    return last.(results)
end

function _apply_operator(
    M::DistributedOperator{T,W,K,:asyncmap}, func0_symbol, ensemble::AbstractEnsemble
) where {T,W,K}
    members = get_ensemble_members(ensemble)
    output_array = Vector{eltype(members)}(undef, size(members))
    _run_parallel(func0_symbol, collect(enumerate(members)), output_array, M.worker_pool)
    return output_array
end

function split_clean_noisy(
    M::DistributedOperator{T,W,K,D}, ensemble_obs::AbstractEnsemble
) where {T<:AbstractNoisyOperator,W,K,D}
    return split_clean_noisy(M.op, ensemble_obs)
end
function xor_seed!(
    M::DistributedOperator{T,W,K,D}, seed_mod::UInt
) where {T<:AbstractNoisyOperator,W,K,D}
    return xor_seed!(M.op, seed_mod)
end

get_state_keys(M::DistributedOperator) = get_state_keys(M.op)

# Based on Base.asyncmap
function _run_parallel(f0_symbol, data, output_array, pool=default_worker_pool())
    jobs = RemoteChannel(() -> Channel{Tuple{Int,eltype(data)}}(32))
    results = RemoteChannel(() -> Channel{Tuple}(32))

    @assert length(data) == length(output_array)
    n = length(data)

    function worker_task(f0_symbol, jobs, results)
        retval = nothing
        try
            f = f0_symbol()
            try
                while true
                    (job_id, job) = take!(jobs)
                    out = f(job)
                    put!(results, (job_id, out))
                end
            catch ex
                if isa(ex, RemoteException) &&
                    isa(ex.captured.ex, InvalidStateException) &&
                    ex.captured.ex.state == :closed
                elseif isa(ex, InvalidStateException) && ex.state == :closed
                else
                    rethrow()
                end
            end
        catch e
            close(jobs)
            close(results)
            retval = Base.capture_exception(e, Base.catch_backtrace())
        end
        @debug "for process $(myid()), retval = $(retval)"
        return retval
    end

    worker_tasks = []
    for p in workers(pool)
        @debug "Sending task to worker $p"
        t = remotecall(worker_task, p, f0_symbol, jobs, results)
        push!(worker_tasks, t)
    end

    ex_driver = nothing
    try
        @sync begin
            @async begin
                ex_put = nothing
                try
                    @debug "Putting jobs in queue"
                    for i_di in enumerate(data)
                        yield()
                        @debug "Putting job $(i_di[1]) in queue"
                        put!(jobs, i_di)
                    end
                catch ex
                    if isa(ex, InvalidStateException)
                        # channel could be closed due to exceptions in the async tasks,
                        # we propagate those errors, if any, over the `put!` failing
                        # due to a closed channel.
                        ex_put = ex
                    else
                        rethrow()
                    end
                end
                @debug "Closing jobs channels: $ex_put"
                close(jobs)
                (ex_put !== nothing) && throw(ex_put)
            end

            @async begin
                ex_take = nothing
                @debug "Reading results from queue"
                @elapsed while n > 0 && isopen(results)
                    try
                        yield()
                        @debug "Taking result $(n) from queue"
                        job_id, out = take!(results)
                        output_array[job_id] = out
                        n = n - 1
                    catch ex
                        if isa(ex, InvalidStateException)
                            # This is probably just the error about `take!` failing.
                            # Let's hold onto it until we're sure there aren't
                            # other exceptions that caused this failure.
                            ex_take = ex
                        else
                            rethrow()
                        end
                    end
                end
                @debug "Closing results channel: $ex_take"
                close(results)
                (ex_take !== nothing) && throw(ex_take)
            end
        end
    catch e
        ex_driver = e
    end

    @debug "Fetching worker return values"
    for (p, t) in zip(workers(pool), worker_tasks)
        v = fetch(t)
        isa(v, Exception) && throw(v)
    end
    return (ex_driver !== nothing) && throw(ex_driver)
end
