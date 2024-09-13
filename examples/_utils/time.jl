export @time_msg

"""Hello"""
macro time_msg(msg, ex)
    quote
        local _msg = $(esc(msg))
        local _msg_str = _msg === nothing ? _msg : string(_msg)
        if _msg_str isa String
            print(_msg_str, ": ")
        end
        @time($(esc(ex)))
    end
end
