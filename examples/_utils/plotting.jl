
function plot_state_over_time(ts, data; make_positive=false, max_dt=100, handler=nothing, plot_kwargs...)

    xs = view(data, 1, :)
    ys = view(data, 2, :)
    zs = view(data, 3, :)

    function handle_infinities!(d)
        if any(isinf, d)
            ex = extrema(x for x in d if !isinf(x))
            mask = isinf.(d)
            d[mask .& (sign.(d) .< 0)] .= ex[1]
            d[mask .& (sign.(d) .> 0)] .= ex[2]
        end
    end
    handle_infinities!(xs)
    handle_infinities!(ys)
    handle_infinities!(zs)

    function handle_zeros!(d)
        if any(iszero, d)
            ex = minimum(x for x in d if !iszero(x))
            mask = iszero.(d)
            d[mask] .= ex
        end
    end
    if make_positive
        handle_zeros!(xs)
        handle_zeros!(ys)
        handle_zeros!(zs)
    end

    function plot_this_thing(;
        xlims=(;low=nothing, high=nothing)
    )
        fig = Figure()

        ## Plot x vs t.
        ax = Axis(fig)
        fig[1, 1] = ax
        scatterlines!(ax, ts, xs; plot_kwargs...)
        ax.xlabel = L"\text{time}"
        ax.ylabel = L"\text{x}"
        ax.ylabelrotation = 0.0
        xlims!(ax; xlims...)

        ## Plot y vs t.
        ax = Axis(fig)
        fig[2, 1] = ax
        scatterlines!(ax, ts, ys; plot_kwargs...)
        ax.xlabel = L"\text{time}"
        ax.ylabel = L"\text{y}"
        ax.ylabelrotation = 0.0
        xlims!(ax; xlims...)

        ## Plot z vs t.
        ax = Axis(fig)
        fig[3, 1] = ax
        scatterlines!(ax, ts, zs; plot_kwargs...)
        ax.xlabel = L"\text{time}"
        ax.ylabel = L"\text{z}"
        ax.ylabelrotation = 0.0
        xlims!(ax; xlims...)

        if !isnothing(handler)
            handler(fig)
        end
        return fig
    end

    fig = plot_this_thing()
    display(fig)
    for low = ts[1]:max_dt:ts[end]
        high = min(low + max_dt, ts[end])
        fig = plot_this_thing(; xlims=(;low, high))
        display(fig)
        break
    end
end


function plot_error_metric_over_time(ts, metrics; max_dt = 50, handler=nothing, plot_kwargs...)
    function plot_this_thing(;
        xlims=(;low=nothing, high=nothing)
    )
        fig = Figure()
        ax = Axis(fig)
        fig[1, 1] = ax
        plot_disjoint_lines!(ax, ts, metrics; plot_kwargs...)

        ax.xlabel = L"\text{time}"
        ax.ylabel = L"\text{metric}"
        ax.ylabelrotation = 0.0
        xlims!(ax; xlims...)

        if !isnothing(handler)
            handler(fig)
        end
        return fig
    end

    fig = plot_this_thing()
    display(fig)

    for low = ts[1]:max_dt:ts[end]
        high = min(low + max_dt, ts[end])
        fig = plot_this_thing(; xlims=(;low, high))
        display(fig)
        break
    end
end
