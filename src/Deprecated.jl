## ================================================================================
## LEGACY ON TIMESTAMPS, TODO DEPRECATE
##=================================================================================


Base.promote_rule(::Type{DateTime}, ::Type{ZonedDateTime}) = DateTime
function Base.convert(::Type{DateTime}, ts::ZonedDateTime)
    @warn "DFG now uses ZonedDateTime, temporary promoting and converting to DateTime local time"
    return DateTime(ts, Local)
end

## ================================================================================
## Deprecate before v0.19 - Kept longer with error
##=================================================================================

Base.getproperty(x::VariableNodeData,f::Symbol) = begin
  if f == :inferdim
    error("vnd.inferdim::Float64 was deprecated and is now obsolete, use vnd.infoPerCoord::Vector{Float64} instead")
  else
    getfield(x,f)
  end
end

function Base.setproperty!(x::VariableNodeData, f::Symbol, val)
  if f == :inferdim
    error("vnd.inferdim::Float64 was deprecated and is now obsolete, use vnd.infoPerCoord::Vector{Float64} instead")
  end
  return setfield!(x, f, convert(fieldtype(typeof(x), f), val))
end

Base.getproperty(x::PackedVariableNodeData,f::Symbol) = begin
  if f == :inferdim
    error("pvnd.inferdim::Float64 was deprecated and is now obsolete, use vnd.infoPerCoord::Vector{Float64} instead")
  else
    getfield(x,f)
  end
end

function Base.setproperty!(x::PackedVariableNodeData, f::Symbol, val)
  if f == :inferdim
    error("pvnd.inferdim::Float64 was deprecated and is now obsolete, use vnd.infoPerCoord::Vector{Float64} instead")
  end
  return setfield!(x, f, convert(fieldtype(typeof(x), f), val))
end



function VariableNodeData(val::Vector,
                          bw::AbstractMatrix{<:Real},
                          BayesNetOutVertIDs::AbstractVector{Symbol},
                          dimIDs::AbstractVector{Int},
                          dims::Int,
                          eliminated::Bool,
                          BayesNetVertID::Symbol,
                          separator::AbstractVector{Symbol},
                          variableType,
                          initialized::Bool,
                          inferdim::Real,
                          w...; kw...)
  error("VariableNodeData field inferdim was deprecated and is now obsolete, use infoPerCoord instead")
end



## ================================================================================
## Deprecate before v0.19
##=================================================================================

@deprecate dfgplot(w...;kw...) plotDFG(w...;kw...)

export FunctorInferenceType, PackedInferenceType

const FunctorInferenceType = AbstractFactor       # will eventually deprecate
const PackedInferenceType = AbstractPackedFactor  # will eventually deprecate

## ================================================================================
## Deprecate before v0.20
##=================================================================================

export DefaultDFG

const DefaultDFG = LightDFG

#