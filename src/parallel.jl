export AbstractParallelStrategy, AbstractParallelWorker
export run_partial_operator
export ParallelWorker
export divvy_among_workers

abstract type AbstractParallelStrategy end
abstract type AbstractParallelWorker end

"""Unstable interface"""
function run_partial_operator end

"""Unstable interface"""
struct ParallelWorker <: AbstractParallelWorker
    num_workers::Any
    worker_id::Any
end

"""
    divvy_among_workers(N, worker_id, num_workers)

Statically partition the `N` jobs among `num_workers` workers and return the job range for
this worker.

Given a number of jobs `N`, a number of workers `num_workers, and a particular worker's id
`worker_id` in the range 1 to `num_workers`, the job's are partitioned such that every
worker has `floor(N / num_workers)` jobs, except `N % num_workers` will have one extra
job.
"""
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
