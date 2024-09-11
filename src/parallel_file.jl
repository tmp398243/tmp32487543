using Distributed: pmap
using JLD2: jldsave, load

export FileBasedPartial

struct FileBasedPartial <: AbstractParallelStrategy
    target_path::Any
    work_path::Any
end

function run_partial_operator(strat::FileBasedPartial, worker::ParallelWorker,
        operator, ensemble::AbstractEnsemble; reset_state_keys)
    if ispath(strat.target_path)
        error("Can't write to $(strat.target_path). It already exists")
    end
    closer = worker.worker_id == 1 && worker.num_workers == 1
    ensemble_dir = "$(strat.work_path)_ensemble"
    mkpath(ensemble_dir)

    ## Divide ensemble members among workers.
    ensemble_members = get_ensemble_members(ensemble)
    if closer
        my_slice = enumerate(ensemble_members)
    else
        N = get_ensemble_size(ensemble)
        s, e = divvy_among_workers(N, worker.worker_id, worker.num_workers)
        @debug "  - Doing $(e-s+1) ensemble members: $(s) through $(e)."
        my_slice = zip(s:e, ensemble_members[s:e])
    end

    ## Define function for operating on each ensemble member.
    num_completed = 0
    function wrapper(args)
        (i, em0) = args

        ## Skip if file already exists.
        filepath = joinpath(ensemble_dir, "$(i).jld2")
        if isfile(filepath)
            return
        end

        @debug "  - Doing ensemble member $(i)"
        em = operator(em0)
        jldsave(filepath; data = em)
        num_completed += 1
    end

    ## Run transition function on each ensemble member for this worker.
    asyncmap(wrapper, my_slice; ntasks = 4)

    if closer
        ## Save filter to target_path.
        save_ensemble(ensemble, strat.target_path;
            existing_member_directory = ensemble_dir, reset_state_keys)
    end
    return closer, num_completed
end
