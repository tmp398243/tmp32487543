export AbstractParallelStrategy, AbstractParallelWorker
export run_partial_operator
export ParallelWorker
export divvy_among_workers

abstract type AbstractParallelStrategy end
abstract type AbstractParallelWorker end

function run_partial_operator end

struct ParallelWorker <: AbstractParallelWorker
    num_workers::Any
    worker_id::Any
end

function divvy_among_workers(N, worker_id, num_workers)
    base_work, extra_work = divrem(N, num_workers)

    ## Distribute work almost evenly
    work_per_job = fill(base_work, num_workers)
    work_per_job[1:extra_work] .+= 1

    ## Calculate the starting index for this process
    start_index = sum(work_per_job[1:(worker_id - 1)]) + 1

    ## Calculate the ending index for this process
    end_index = start_index + work_per_job[worker_id] - 1

    return start_index, end_index
end
