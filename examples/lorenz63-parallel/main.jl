# # Lorenz63 example
# Set up environment

## Fix for https://github.com/fredrikekre/Literate.jl/issues/251
include(x) = Base.include(@__MODULE__, x)
let
    s = current_task().storage
    if !isnothing(s)
        s[:SOURCE_PATH] = @__FILE__
    end
end

## Install unregistered packages.
using Pkg: Pkg

using Ensembles
try
    using Lorenz63: Lorenz63
catch
    Ensembles.install(:Lorenz63)
end

## Define a macro for doing imports to avoid duplicating it for remote processes later on.
macro initial_imports()
    return esc(
        quote
            using Ensembles
            using LinearAlgebra: norm
            using Distributed:
                addprocs, rmprocs, @everywhere, remotecall, fetch, WorkerPool
            using Test: @test
            using Random: Random

            using Lorenz63: Lorenz63
            ext = Ensembles.get_extension(Ensembles, :Lorenz63Ext)
            using .ext
        end,
    )
end

@initial_imports
worker_initial_imports = @macroexpand1 @initial_imports

include("../_utils/time.jl")

# Define how to make the initial ensemble.
function generate_ensemble(params::Dict)
    seed = params["ensemble"]["seed"]
    ensemble_size = params["ensemble"]["size"]
    prior_type = params["ensemble"]["prior"]

    members = Vector{Dict{Symbol,Any}}(undef, ensemble_size)
    if prior_type == "gaussian"
        rng = Random.MersenneTwister(seed)
        prior_mean, prior_std = params["ensemble"]["prior_params"]
        for i in 1:ensemble_size
            data = prior_mean .+ prior_std .* randn(rng, 3)
            state = Dict{Symbol,Any}(:state => data)
            members[i] = state
        end
    else
        throw(ArgumentError("Invalid prior type: $prior_type"))
    end

    ensemble = Ensemble(members)
    return ensemble
end;

# Define parameters.
params = Dict(
    "format" => "v0.1",
    "transition" => Dict(
        "sigma" => 10,
        "rho" => 28,
        "beta" => 8 / 3,
        "scaling" => 1,
        "ministep_nt" => missing,
        "ministep_dt" => 0.05,
    ),
    "observation" => Dict("noise_scale" => 2, "timestep_size" => 0.1, "num_timesteps" => 5),
    "ensemble" => Dict(
        "size" => 5,
        "seed" => 9347215,
        "prior" => "gaussian",
        "prior_params" => [0.0, 1.0],
    ),
    "spinup" => Dict(
        "num_timesteps" => 5,
        "transition_noise_scale" => 0.0,
    ),
);

# Seed for reproducibility.
Random.seed!(1983745)

# Make operators.
transitioner = Lorenz63Model(; params)
observer = NoisyObserver(get_state_keys(transitioner); params);

# Set seed for ground-truth simulation.
Random.seed!(0xfee55e45)
xor_seed!(observer, UInt64(0x243ecae5))

# Define observation times
observation_times = let
    step = params["observation"]["timestep_size"]
    length = params["observation"]["num_timesteps"]
    range(; start=0, length, step)
end

# Generate synthetic ground-truth observations.
if !(@isdefined ground_truth) || isnothing(ground_truth)
    ground_truth = @time let
        state0 = Dict{Symbol,Any}(:state => randn(3))

        ## Set seed for ground-truth simulation.
        Random.seed!(0xfee55e45)
        xor_seed!(observer, UInt64(0x243ecae5))

        ## Generate states and observations.
        t0 = 0.0
        states = Vector{Dict{Symbol,Any}}(undef, length(observation_times))
        observations = Vector{Dict{Symbol,Any}}(undef, length(observation_times))
        let state = state0
            for (i, t) in enumerate(observation_times)
                state = transitioner(state, t0, t)
                obs = observer(state)
                states[i] = state
                observations[i] = split_clean_noisy(observer, obs)[2]
                t0 = t
            end
        end
        (; states, observations)
    end
    println("  ^ timing for making ground truth observations")
    ground_truth_states_vec = get_ensemble_matrix([:state], ground_truth.states)
    ground_truth_obs_vec = get_ensemble_matrix([:state], ground_truth.observations)
end;

# Make initial ensemble.

if !(@isdefined ensemble_initial0) || isnothing(ensemble_initial0)
    ensemble_initial0 = generate_ensemble(params)
end

ensemble_initial0 = generate_ensemble(params);
ensemble_initial = Ensemble(ensemble_initial0, ensemble_initial0.members, [:state]);

t_index_end = params["spinup"]["num_timesteps"]
observation_times = observation_times[1:t_index_end]
ground_truth_observations = ground_truth.observations[1:t_index_end]
transition_noise = params["spinup"]["transition_noise_scale"]

# Choose filtering algorithm.
filter = nothing

# Run sequential algorithm.
if !(@isdefined ensembles_sequential) || isnothing(ensembles_sequential)
    ensembles_sequential =
        let t_index_end = params["spinup"]["num_timesteps"],
            observation_times = observation_times[1:t_index_end],
            ground_truth_observations = ground_truth.observations[1:t_index_end],
            ensemble = ensemble_initial0,
            t0 = 0.0,
            transition_noise = params["spinup"]["transition_noise_scale"]

            Random.seed!(0x3289745)
            xor_seed!(observer, UInt64(0x375ef928))

            logs = []
            ensembles = []
            @time begin
                push!(ensembles, (; ensemble, t=t0))
                for (t, y_obs) in zip(observation_times, ground_truth_observations)
                    ## Advance ensemble to time t.
                    ensemble = transitioner(ensemble, t0, t; inplace=false)

                    ## Keep ensemble separated.
                    if transition_noise != 0
                        for em in ensemble.members
                            em[:state] .+= transition_noise .* Random.randn(3)
                        end
                    end

                    ## Take observation at time t.
                    ensemble_obs = observer(ensemble)
                    ensemble_obs_clean, ensemble_obs_noisy = split_clean_noisy(
                        observer, ensemble_obs
                    )

                    ## Record.
                    push!(
                        ensembles, (; ensemble, ensemble_obs_clean, ensemble_obs_noisy, t)
                    )

                    ## Assimilate observation
                    log_data = Dict{Symbol,Any}()
                    (posterior, timing...) = @timed assimilate_data(
                        filter,
                        ensemble,
                        ensemble_obs_clean,
                        ensemble_obs_noisy,
                        y_obs,
                        log_data,
                    )
                    log_data[:timing] = timing
                    ensemble = posterior

                    ## Record.
                    push!(ensembles, (; ensemble, t))
                    push!(logs, log_data)

                    ## Let time pass.
                    t0 = t
                end
            end
            println("  ^ timing for making initial ensemble")
            ensembles
        end
end

# Run with file-based parallelism.
worker_ids = addprocs(4; exeflags="--project=$(Base.active_project())")
worker_ids_driver = vcat([1], worker_ids)
try
    @everywhere worker_ids_driver begin
        println("I am here")
        $worker_initial_imports
        function worker_transition(run_dir, k, t, t0, params, worker_id, num_workers)
            try
                local worker = ParallelWorker(num_workers, worker_id)
                local ensemble_path = joinpath(run_dir, "ensemble_$(k-1)_posterior")
                local ensemble = load_ensemble(ensemble_path)
                local tmp_filepath = joinpath(run_dir, "intermediate_trans_$(k-1)_to_$(k)")
                local output_filepath = joinpath(run_dir, "ensemble_$(k)_prior")
                local parallel_strategy = FileBasedPartial(output_filepath, tmp_filepath)
                local transitioner = Lorenz63Model(; params)
                local closer, num_completed = run_partial_operator(
                    parallel_strategy,
                    worker,
                    em -> transitioner(em, t, t0),
                    ensemble;
                    reset_state_keys=false,
                )
                if closer
                    @debug "Transition: closer did $num_completed"
                else
                    @debug "Transition: worker $worker_id did $num_completed"
                end
            catch e
                return e
            end
        end

        function worker_observer(run_dir, k, params, worker_id, num_workers)
            try
                local worker = ParallelWorker(num_workers, worker_id)
                local ensemble_path = joinpath(run_dir, "ensemble_$(k)_prior")
                local ensemble = load_ensemble(ensemble_path)
                local tmp_filepath = joinpath(run_dir, "intermediate_obs_$(k)")
                local output_filepath = joinpath(run_dir, "ensemble_$(k)_obs_prior")
                local parallel_strategy = FileBasedPartial(output_filepath, tmp_filepath)
                local transitioner = Lorenz63Model(; params)
                local observer = NoisyObserver(get_state_keys(transitioner); params)
                xor_seed!(observer, UInt64(worker_id * num_workers - 1))
                local closer, num_completed = run_partial_operator(
                    parallel_strategy, worker, observer, ensemble; reset_state_keys=false
                )
                if closer
                    @debug "Observer: closer did $num_completed"
                else
                    @debug "Observer: worker $worker_id did $num_completed"
                end
            catch e
                return e
            end
        end
    end

    for observer_type in [:sequential, :not_sequential]
        Random.seed!(0x3289745)
        xor_seed!(observer, UInt64(0x375ef928))

        run_dir = tempname("."; cleanup=false)
        @show run_dir
        mkpath(run_dir)
        save_ensemble(ensemble_initial, joinpath(run_dir, "ensemble_0_posterior"))

        logs = []
        ensembles = []
        @time_msg "Run ensemble parallel" let ensemble = ensemble_initial
            t0 = 0.0
            push!(ensembles, (; ensemble, t=t0))
            for (k, (t, y_obs)) in
                enumerate(zip(observation_times, ground_truth.observations))
                ## Advance ensemble to time t.
                worker_tasks = []
                for (i, p) in enumerate(worker_ids)
                    task = remotecall(
                        Main.worker_transition,
                        p,
                        run_dir,
                        k,
                        t0,
                        t,
                        params,
                        i,
                        length(worker_ids),
                    )
                    push!(worker_tasks, task)
                end

                for task in worker_tasks
                    v = fetch(task)
                    isa(v, Exception) && throw(v)
                end
                Main.worker_transition(run_dir, k, t0, t, params, 1, 1)
                output_filepath = joinpath(run_dir, "ensemble_$(k)_prior")
                ensemble = load_ensemble(output_filepath)

                ## Take observation at time t.
                if observer_type == :sequential
                    println("Time $t: observer rng $(observer.rng)")
                    ensemble_obs = observer(ensemble)
                    println("Time $t: observer rng $(observer.rng)")
                else
                    worker_tasks = []
                    for (i, p) in enumerate(worker_ids)
                        task = remotecall(
                            Main.worker_observer,
                            p,
                            run_dir,
                            k,
                            params,
                            i,
                            length(worker_ids),
                        )
                        push!(worker_tasks, task)
                    end

                    for task in worker_tasks
                        v = fetch(task)
                        isa(v, Exception) && throw(v)
                    end
                    Main.worker_observer(run_dir, k, params, 1, 1)
                    output_filepath = joinpath(run_dir, "ensemble_$(k)_obs_prior")
                    ensemble_obs = load_ensemble(output_filepath)
                end

                ensemble_obs_clean, ensemble_obs_noisy = split_clean_noisy(
                    observer, ensemble_obs
                )
                println(
                    "Time $t : noise norm $(norm(get_ensemble_matrix(ensemble_obs_clean) .- get_ensemble_matrix(ensemble_obs_noisy)))",
                )

                ## Record.
                push!(ensembles, (; ensemble, ensemble_obs_clean, ensemble_obs_noisy, t))

                ## Assimilate observation
                log_data = Dict{Symbol,Any}()
                (posterior, timing...) = @timed assimilate_data(
                    filter,
                    ensemble,
                    ensemble_obs_clean,
                    ensemble_obs_noisy,
                    y_obs,
                    log_data,
                )
                log_data[:timing] = timing
                println(
                    "Time $t : posterior norm $(norm(get_ensemble_matrix(ensemble) .- get_ensemble_matrix(posterior)))",
                )
                ensemble = posterior
                save_ensemble(ensemble, joinpath(run_dir, "ensemble_$(k)_posterior"))

                ## Record.
                push!(ensembles, (; ensemble, t))
                push!(logs, log_data)

                ## Let time pass.
                t0 = t
            end
        end
        ensembles_parallel = ensembles

        ## Print out some info to make sure the results are the same.
        let
            ensemble_obs_noisy_diffs = []
            ensemble_obs_clean_diffs = []
            ensemble_diffs = []
            for (i, (e, ep)) in enumerate(zip(ensembles_sequential, ensembles_parallel))
                em = get_ensemble_matrix(e.ensemble)
                epm = get_ensemble_matrix(ep.ensemble)
                push!(ensemble_diffs, norm(em .- epm))
                println("Index $i, t $(e.t) $(ep.t):")
                println("    ensemble: $(ensemble_diffs[end])")
                if hasfield(typeof(e), :ensemble_obs_noisy)
                    em_on = get_ensemble_matrix(e.ensemble_obs_noisy)
                    epm_on = get_ensemble_matrix(ep.ensemble_obs_noisy)
                    push!(ensemble_obs_noisy_diffs, norm(em_on .- epm_on))
                    println("    ensemble_obs_noisy: $(ensemble_obs_noisy_diffs[end])")

                    em_oc = get_ensemble_matrix(e.ensemble_obs_clean)
                    epm_oc = get_ensemble_matrix(ep.ensemble_obs_clean)
                    push!(ensemble_obs_clean_diffs, norm(em_oc .- epm_oc))
                    println("    ensemble_obs_clean: $(ensemble_obs_clean_diffs[end])")

                    println("    noise norm S: $(norm(em_oc .- em_on))")
                    println("    noise norm P: $(norm(epm_oc .- epm_on))")
                end
            end
            if observer_type == :sequential
                @test all(ensemble_diffs .== 0)
                @test all(ensemble_obs_noisy_diffs .== 0)
                @test all(ensemble_obs_clean_diffs .== 0)
            else
                @test ensemble_diffs[1] == 0
                @test ensemble_obs_clean_diffs[1] == 0
            end
        end
    end
finally
    rmprocs(worker_ids)
end;

# Now do the transition in parallel, using the same observations as the sequential code.
worker_ids = addprocs(4; exeflags="--project=$(Base.active_project())")
try
    @everywhere worker_ids $worker_initial_imports

    for distributed_type in [:pmap, :distributed_for, :asyncmap]
        Random.seed!(0x3289745)
        xor_seed!(observer, UInt64(0x375ef928))

        ensembles_parallel =
            let transitioner = DistributedOperator(transitioner, Val(:pmap))
                logs = []
                ensembles = []
                @time_msg "Run ensemble parallel" let ensemble = ensemble_initial
                    t0 = 0.0
                    push!(ensembles, (; ensemble, t=t0))
                    i_obs = 2
                    for (t, y_obs) in zip(observation_times, ground_truth.observations)
                        ## Advance ensemble to time t.
                        ensemble = transitioner(ensemble, t0, t; inplace=false)

                        ## Get observation at time t.
                        ensemble_obs_clean = ensembles_sequential[i_obs].ensemble_obs_clean
                        ensemble_obs_noisy = ensembles_sequential[i_obs].ensemble_obs_noisy
                        i_obs += 2
                        println(
                            "Time $t : noise norm $(norm(get_ensemble_matrix(ensemble_obs_clean) .- get_ensemble_matrix(ensemble_obs_noisy)))",
                        )

                        ## Record.
                        push!(
                            ensembles,
                            (; ensemble, ensemble_obs_clean, ensemble_obs_noisy, t),
                        )

                        ## Assimilate observation
                        log_data = Dict{Symbol,Any}()
                        (posterior, timing...) = @timed assimilate_data(
                            filter,
                            ensemble,
                            ensemble_obs_clean,
                            ensemble_obs_noisy,
                            y_obs,
                            log_data,
                        )
                        log_data[:timing] = timing
                        println(
                            "Time $t : posterior norm $(norm(get_ensemble_matrix(ensemble) .- get_ensemble_matrix(posterior)))",
                        )
                        ensemble = posterior

                        ## Record.
                        push!(ensembles, (; ensemble, t))
                        push!(logs, log_data)

                        ## Let time pass.
                        t0 = t
                    end
                end
                ensembles
            end

        ## Print out some info to make sure the results are the same.
        let
            ensemble_obs_noisy_diffs = []
            ensemble_obs_clean_diffs = []
            ensemble_diffs = []
            for (i, (e, ep)) in enumerate(zip(ensembles_sequential, ensembles_parallel))
                em = get_ensemble_matrix(e.ensemble)
                epm = get_ensemble_matrix(ep.ensemble)
                push!(ensemble_diffs, norm(em .- epm))
                println("Index $i, t $(e.t) $(ep.t):")
                println("    ensemble: $(ensemble_diffs[end])")
                if hasfield(typeof(e), :ensemble_obs_noisy)
                    em_on = get_ensemble_matrix(e.ensemble_obs_noisy)
                    epm_on = get_ensemble_matrix(ep.ensemble_obs_noisy)
                    push!(ensemble_obs_noisy_diffs, norm(em_on .- epm_on))
                    println("    ensemble_obs_noisy: $(ensemble_obs_noisy_diffs[end])")

                    em_oc = get_ensemble_matrix(e.ensemble_obs_clean)
                    epm_oc = get_ensemble_matrix(ep.ensemble_obs_clean)
                    push!(ensemble_obs_clean_diffs, norm(em_oc .- epm_oc))
                    println("    ensemble_obs_clean: $(ensemble_obs_clean_diffs[end])")

                    println("    noise norm S: $(norm(em_oc .- em_on))")
                    println("    noise norm P: $(norm(epm_oc .- epm_on))")
                end
            end
            @test all(ensemble_diffs .== 0)
            @test all(ensemble_obs_noisy_diffs .== 0)
            @test all(ensemble_obs_clean_diffs .== 0)
        end
    end
finally
    rmprocs(worker_ids)
end;

# Now do it all in parallel.
worker_ids = addprocs(6; exeflags="--project=$(Base.active_project())")
ensembles_parallel = try
    worker_pool = WorkerPool(worker_ids[3:end])
    @everywhere worker_ids $worker_initial_imports

    Random.seed!(0x3289745)
    xor_seed!(observer, UInt64(0x375ef928))

    ensembles =
        let transitioner = DistributedOperator(transitioner, worker_pool, Val(:pmap)),
            observer = DistributedOperator(observer, worker_pool)

            logs = []
            ensembles = []
            @time_msg "Run ensemble parallel" let ensemble = ensemble_initial
                t0 = 0.0
                push!(ensembles, (; ensemble, t=t0))
                for (t, y_obs) in zip(observation_times, ground_truth.observations)
                    ## Advance ensemble to time t.
                    ensemble = transitioner(ensemble, t0, t; inplace=false)

                    ## Take observation at time t.
                    ensemble_obs = observer(ensemble)
                    ensemble_obs_clean, ensemble_obs_noisy = split_clean_noisy(
                        observer, ensemble_obs
                    )
                    println(
                        "Time $t : noise norm $(norm(get_ensemble_matrix(ensemble_obs_clean) .- get_ensemble_matrix(ensemble_obs_noisy)))",
                    )

                    ## Record.
                    push!(
                        ensembles,
                        (; ensemble, ensemble_obs_clean, ensemble_obs_noisy, t),
                    )

                    ## Assimilate observation
                    log_data = Dict{Symbol,Any}()
                    (posterior, timing...) = @timed assimilate_data(
                        filter,
                        ensemble,
                        ensemble_obs_clean,
                        ensemble_obs_noisy,
                        y_obs,
                        log_data,
                    )
                    log_data[:timing] = timing
                    println(
                        "Time $t : posterior norm $(norm(get_ensemble_matrix(ensemble) .- get_ensemble_matrix(posterior)))",
                    )
                    ensemble = posterior

                    ## Record.
                    push!(ensembles, (; ensemble, t))
                    push!(logs, log_data)

                    ## Let time pass.
                    t0 = t
                end
            end
            ensembles
        end
finally
    rmprocs(worker_ids)
end;

# Print out some info to make sure the results are the same, except the noise should be different.
for (i, (e, ep)) in enumerate(zip(ensembles_sequential, ensembles_parallel))
    em = get_ensemble_matrix(e.ensemble)
    epm = get_ensemble_matrix(ep.ensemble)
    println("Index $i, t $(e.t) $(ep.t):")
    println("    ensemble: $(norm(em .- epm))")
    if hasfield(typeof(e), :ensemble_obs_noisy)
        em_on = get_ensemble_matrix(e.ensemble_obs_noisy)
        epm_on = get_ensemble_matrix(ep.ensemble_obs_noisy)
        println("    ensemble_obs_noisy: $(norm(em_on .- epm_on))")

        em_oc = get_ensemble_matrix(e.ensemble_obs_clean)
        epm_oc = get_ensemble_matrix(ep.ensemble_obs_clean)
        println("    ensemble_obs_clean: $(norm(em_oc .- epm_oc))")

        println("    noise norm S: $(norm(em_oc .- em_on))")
        println("    noise norm P: $(norm(epm_oc .- epm_on))")
    end
end;

# Maybe clean up a little.
try
    Pkg.rm("Lorenz63")
catch e
    @warn e
end
