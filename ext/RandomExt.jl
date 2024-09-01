"This module extends Ensembles with functionality from Random."
module RandomExt

using Ensembles: Ensembles
using Random

"""
    greeting()

Call [`Ensembles.greeting`](@ref) with a random name.


# Examples

```jldoctest
julia> @test true;

```

"""
Ensembles.greeting() = Ensembles.greeting(rand(5))

end
