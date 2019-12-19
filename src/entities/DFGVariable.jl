#TODO don't know what to do if it is uninitalized
#so for now defining a Singleton for the default
struct SingletonInferenceVariable <: InferenceVariable end

"""
$(TYPEDEF)

Main data container for Level2 data -- see developer wiki.
"""
mutable struct VariableNodeData{T<:InferenceVariable}
  val::Array{Float64,2}
  bw::Array{Float64,2}
  BayesNetOutVertIDs::Array{Symbol,1}
  dimIDs::Array{Int,1} # Likely deprecate
  dims::Int
  eliminated::Bool
  BayesNetVertID::Symbol #  Union{Nothing, }
  separator::Array{Symbol,1}
  softtype::T
  initialized::Bool
  inferdim::Float64
  ismargin::Bool
  dontmargin::Bool
  solveInProgress::Int
  # Tonio surprise TODO
  # frontalonly::Bool
end

VariableNodeData(val::Array{Float64,2},
               bw::Array{Float64,2},
               BayesNetOutVertIDs::Array{Symbol,1},
               dimIDs::Array{Int,1},
               dims::Int,eliminated::Bool,
               BayesNetVertID::Symbol,
               separator::Array{Symbol,1},
               softtype::T,
               initialized::Bool,
               inferdim::Float64,
               ismargin::Bool,
               dontmargin::Bool,
               solveInProgress::Int=0) where T <: InferenceVariable =
                  VariableNodeData{T}(val,bw,BayesNetOutVertIDs,dimIDs,dims,eliminated,BayesNetVertID,separator,
                                      softtype::T,initialized,inferdim,ismargin,dontmargin, solveInProgress)


function VariableNodeData()
    st = stacktrace()
    @warn "VariableNodeData() is deprecated please use VariableNodeData{T}() or VariableNodeData(softtype::T) where T <: InferenceVariable. Enable DEBUG logging for stack trace."
    @debug st
    VariableNodeData{InferenceVariable}(zeros(1,1), zeros(1,1), Symbol[], Int[], 0, false, :NOTHING, Symbol[], SingletonInferenceVariable(), false, 0.0, false, false, 0)
end

VariableNodeData{T}() where {T <:InferenceVariable} =
        VariableNodeData{T}(zeros(1,1), zeros(1,1), Symbol[], Int[], 0, false, :NOTHING, Symbol[], T(), false, 0.0, false, false, 0)

VariableNodeData(softtype::T) where T <: InferenceVariable =
        VariableNodeData{T}(zeros(1,1), zeros(1,1), Symbol[], Int[], 0, false, :NOTHING, Symbol[], softtype, false, 0.0, false, false, 0)

"""
$(TYPEDEF)
"""
mutable struct PackedVariableNodeData
  vecval::Array{Float64,1}
  dimval::Int
  vecbw::Array{Float64,1}
  dimbw::Int
  BayesNetOutVertIDs::Array{Symbol,1} # Int
  dimIDs::Array{Int,1}
  dims::Int
  eliminated::Bool
  BayesNetVertID::Symbol # Int
  separator::Array{Symbol,1} # Int
  softtype::String
  initialized::Bool
  inferdim::Float64
  ismargin::Bool
  dontmargin::Bool
  solveInProgress::Int
  PackedVariableNodeData() = new()
  PackedVariableNodeData(x1::Vector{Float64},
                         x2::Int,
                         x3::Vector{Float64},
                         x4::Int,
                         x5::Vector{Symbol}, # Int
                         x6::Vector{Int},
                         x7::Int,
                         x8::Bool,
                         x9::Symbol, # Int
                         x10::Vector{Symbol}, # Int
                         x11::String,
                         x12::Bool,
                         x13::Float64,
                         x14::Bool,
                         x15::Bool,
                         x16::Int) = new(x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11,x12,x13,x14,x15,x16)
end

# AbstractPointParametricEst interface
abstract type AbstractPointParametricEst end
"""
    $TYPEDEF

Data container to store Parameteric Point Estimate (PPE) for mean and max.
"""
struct MeanMaxPPE <: AbstractPointParametricEst
    solverKey::Symbol #repeated because of Sam's request
    suggested::Vector{Float64}
    max::Vector{Float64}
    mean::Vector{Float64}
    lastUpdatedTimestamp::DateTime
end
MeanMaxPPE(solverKey::Symbol, suggested::Vector{Float64}, max::Vector{Float64},mean::Vector{Float64}) = MeanMaxPPE(solverKey, suggested, max, mean, now())

getMaxPPE(est::AbstractPointParametricEst) = est.max
getMeanPPE(est::AbstractPointParametricEst) = est.mean
getSuggestedPPE(est::AbstractPointParametricEst) = est.suggested
getLastUpdatedTimestamp(est::AbstractPointParametricEst) = est.lastUpdatedTimestamp


VariableEstimate(params...) = errror("VariableEstimate is depreciated, please use MeanMaxPPE")


"""
    $(TYPEDEF)
Fundamental structure for a DFG variable with fields:
"""
mutable struct DFGVariable <: AbstractDFGVariable
    label::Symbol
    timestamp::DateTime
    tags::Vector{Symbol}
    estimateDict::Dict{Symbol, <: AbstractPointParametricEst}
    solverDataDict::Dict{Symbol, VariableNodeData}
    smallData::Dict{String, String}
    bigData::Dict{Symbol, AbstractBigDataEntry}
    solvable::Int
    _internalId::Int64
end

"""
    $SIGNATURES
DFGVariable constructors.
"""
function DFGVariable(label::Symbol, _internalId::Int64 = 0) #where {T <:InferenceVariable}
    st = stacktrace()
    @warn "DFGVariable(label::Symbol, _internalId::Int64 = 0) is depreciated please use DFGVariable(label::Symbol, softtype::T, _internalId::Int64 = 0) where T <: InferenceVariable. Enable DEBUG logging for the stack trace."
    @debug st
    T = InferenceVariable
    DFGVariable(label, now(), Symbol[],
                  Dict{Symbol, MeanMaxPPE}(),
                  Dict{Symbol, VariableNodeData{T}}(:default => VariableNodeData()),
                  Dict{String, String}(),
                  Dict{Symbol,AbstractBigDataEntry}(), 0, _internalId)
end
DFGVariable(label::Symbol, softtype::T, _internalId::Int64 = 0) where {T <: InferenceVariable}  =
    DFGVariable(label, now(), Symbol[],
              Dict{Symbol, MeanMaxPPE}(),
              Dict{Symbol, VariableNodeData{T}}(:default => VariableNodeData{T}()),
              Dict{String, String}(),
              Dict{Symbol,AbstractBigDataEntry}(), 0, _internalId)

"""
    $(SIGNATURES)
Structure for first-class citizens of a DFGVariable.
"""
mutable struct DFGVariableSummary <: AbstractDFGVariable
    label::Symbol
    timestamp::DateTime
    tags::Vector{Symbol}
    estimateDict::Dict{Symbol, <:AbstractPointParametricEst}
    softtypename::Symbol
    _internalId::Int64
end


# SKELETON DFG
"""
    $(TYPEDEF)
Skeleton variable with essentials.
"""
struct SkeletonDFGVariable <: AbstractDFGVariable
    label::Symbol
    tags::Vector{Symbol}
end

SkeletonDFGVariable(label::Symbol) = SkeletonDFGVariable(label, Symbol[])


# Accessors

const VariableDataLevel0 = Union{DFGVariable, DFGVariableSummary, SkeletonDFGVariable}
const VariableDataLevel1 = Union{DFGVariable, DFGVariableSummary}
const VariableDataLevel2 = Union{DFGVariable}


"""
$SIGNATURES

Return the estimates for a variable.
"""
getEstimates(v::VariableDataLevel1) = v.estimateDict

"""
    $SIGNATURES

Return the estimates for a variable.

DEPRECATED, estimates -> getEstimates
"""
function estimates(v::VariableDataLevel1)
    @warn "Deprecated estimates, use getEstimates instead."
    getEstimates(v)
end

"""
    $SIGNATURES

Return a keyed estimate (default is :default) for a variable.
"""
getEstimate(v::VariableDataLevel1, key::Symbol=:default) = haskey(v.estimateDict, key) ? v.estimateDict[key] : nothing

"""
$SIGNATURES

Return a keyed estimate (default is :default) for a variable.
"""
function estimate(v::VariableDataLevel1, key::Symbol=:default)
    @warn "DEPRECATED estimate, use getEstimate instead."
    getEstimate(v, key)
end

"""
   $(SIGNATURES)

Variable nodes softtype information holding a variety of meta data associated with the type of variable stored in that node of the factor graph.

Related

getVariableType
"""
function getSofttype(vnd::VariableNodeData)
  return vnd.softtype
end
function getSofttype(v::DFGVariable; solveKey::Symbol=:default)
  return getSofttype(solverData(v, solveKey))
end

"""
    $SIGNATURES

Retrieve the soft type name symbol for a DFGVariableSummary. ie :Point2, Pose2, etc.
TODO, DO NOT USE v.softtypename in DFGVariableSummary
"""
getSofttype(v::DFGVariableSummary)::Symbol = v.softtypename



"""
$SIGNATURES

Return the softtype for a variable.

DEPRECATED, softtype -> getSofttype
"""
function softtype(v::VariableDataLevel1)
    @warn "Deprecated softtype, use getSofttype instead."
    getSofttype(v)
end


"""
    $SIGNATURES

Retrieve solver data structure stored in a variable.
"""
solverData(v::DFGVariable, key::Symbol=:default) = haskey(v.solverDataDict, key) ? v.solverDataDict[key] : nothing
"""
    $SIGNATURES

Retrieve data structure stored in a variable.
"""
function getData(v::DFGVariable; solveKey::Symbol=:default)::VariableNodeData
  @warn "getData is deprecated, please use solverData()"
  return v.solverDataDict[solveKey]
end
"""
    $SIGNATURES

Set solver data structure stored in a variable.
"""
setSolverData(v::DFGVariable, data::VariableNodeData, key::Symbol=:default) = v.solverDataDict[key] = data
"""
    $SIGNATURES

Set solver data structure stored in a variable.
"""
setSolverData!(v::DFGVariable, data::VariableNodeData, key::Symbol=:default) = setSolverData(v, data, key)

"""
    $SIGNATURES

Get solver data dictionary for a variable.
"""
solverDataDict(v::DFGVariable) = v.solverDataDict

"""
$SIGNATURES

Get the small data for a variable.
"""
smallData(v::DFGVariable) = v.smallData

"""
$SIGNATURES

Set the small data for a variable.
"""
setSmallData!(v::DFGVariable, smallData::String) = v.smallData = smallData

# Todo: Complete this.
bigData(v::DFGVariable) = v.bigData
