
"""
$(TYPEDEF)
Abstract parent struct for DFG variables and factors.
"""
abstract type DFGNode
end

"""
$(TYPEDEF)
An abstract DFG variable.
"""
abstract type AbstractDFGVariable <: DFGNode
end

"""
$(TYPEDEF)
An abstract DFG factor.
"""
abstract type AbstractDFGFactor <: DFGNode
end

"""
$(TYPEDEF)
The common node parameters for variables and factors.
"""
mutable struct DFGNodeParams
    solvable::Int
    _internalId::Int64
    DFGNodeParams(s1=0,s2=0) = new(s1,s2)
end

# import Base: convert
#
# function convert(::Type{Symbol},::DFGNodeParams)
#   # error("WTF")
#   :WTF
# end
# export convert

"""
$(TYPEDEF)
Abstract parent struct for a DFG graph.
"""
abstract type AbstractDFG
end

"""
$(TYPEDEF)
Abstract parent struct for solver parameters.
"""
abstract type AbstractParams end

"""
$(TYPEDEF)
Empty structure for solver parameters.
"""
struct NoSolverParams <: AbstractParams
end

"""
$(TYPEDEF)
Abstract parent struct for big data entry.
"""
abstract type AbstractBigDataEntry end
