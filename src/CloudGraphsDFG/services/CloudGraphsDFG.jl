
"""
    $(SIGNATURES)
Create a new CloudGraphs-based DFG factor graph using a Neo4j.Connection.
"""
function CloudGraphsDFG{T}(neo4jConnection::Neo4j.Connection, userId::String, robotId::String, sessionId::String, encodePackedTypeFunc, getPackedTypeFunc, decodePackedTypeFunc, rebuildFactorMetadata!; description::String="CloudGraphs DFG", solverParams::T=NoSolverParams(), useCache::Bool=false) where T <: AbstractParams
    graph = Neo4j.getgraph(neo4jConnection)
    neo4jInstance = Neo4jInstance(neo4jConnection, graph)
    return CloudGraphsDFG{T}(neo4jInstance, description, userId, robotId, sessionId, encodePackedTypeFunc, getPackedTypeFunc, decodePackedTypeFunc, rebuildFactorMetadata!, Dict{Symbol, Int64}(), Dict{Symbol, DFGVariable}(), Dict{Symbol, DFGFactor}(), Symbol[], solverParams, useCache)
end
"""
    $(SIGNATURES)
Create a new CloudGraphs-based DFG factor graph by specifying the Neo4j connection information.
"""
function CloudGraphsDFG{T}(host::String, port::Int, dbUser::String, dbPassword::String, userId::String, robotId::String, sessionId::String, encodePackedTypeFunc, getPackedTypeFunc, decodePackedTypeFunc, rebuildFactorMetadata!; description::String="CloudGraphs DFG", solverParams::T=NoSolverParams(), useCache::Bool=false) where T <: AbstractParams
    neo4jConnection = Neo4j.Connection(host, port=port, user=dbUser, password=dbPassword);
    return CloudGraphsDFG{T}(neo4jConnection, userId, robotId, sessionId, encodePackedTypeFunc, getPackedTypeFunc, decodePackedTypeFunc, rebuildFactorMetadata!, description=description, solverParams=solverParams, useCache=useCache)
end

"""
    $(SIGNATURES)
Gets an empty and unique CloudGraphsDFG derived from an existing DFG.
"""
function _getDuplicatedEmptyDFG(dfg::CloudGraphsDFG)::CloudGraphsDFG
    count = 0
    sessionId = dfg.sessionId*"_$count"
    while true #do..while loop
        count += 1
        sessionId = dfg.sessionId*"_$count"
        length(_getLabelsFromCyphonQuery(dfg.neo4jInstance, "(node:$(dfg.userId):$(dfg.robotId):$(sessionId))")) == 0 && break
    end
    @debug "Unique+empty copy session name: $sessionId"
    return CloudGraphsDFG{typeof(dfg.solverParams)}(dfg.neo4jInstance.connection, dfg.userId, dfg.robotId, sessionId, dfg.encodePackedTypeFunc, dfg.getPackedTypeFunc, dfg.decodePackedTypeFunc, dfg.rebuildFactorMetadata!, solverParams=deepcopy(dfg.solverParams), description="(Copy of) $(dfg.description)", useCache=dfg.useCache)
end

# Accessors
getLabelDict(dfg::CloudGraphsDFG) = dfg.labelDict
getDescription(dfg::CloudGraphsDFG) = dfg.description
setDescription(dfg::CloudGraphsDFG, description::String) = dfg.description = description
getAddHistory(dfg::CloudGraphsDFG) = dfg.addHistory
getSolverParams(dfg::CloudGraphsDFG) = dfg.solverParams
function setSolverParams(dfg::CloudGraphsDFG, solverParams::T)::T where T <: AbstractParams
    return dfg.solverParams = solverParams
end

function getSerializationModule(dfg::CloudGraphsDFG)::Module where G <: AbstractDFG
    # TODO: If we need to specialize this for RoME etc, here is where we'll change it.
    return Main
end

"""
    $(SIGNATURES)
True if the variable or factor exists in the graph.
"""
function exists(dfg::CloudGraphsDFG, nId::Symbol)
    # If in the dictionary, then shortcut return true
    dfg.useCache && haskey(dfg.labelDict, nId) && return true
    # Otherwise try get it
    nodeId = _tryGetNeoNodeIdFromNodeLabel(dfg.neo4jInstance, dfg.userId, dfg.robotId, dfg.sessionId, nId)
    if nodeId != nothing
        push!(dfg.labelDict, nId=>nodeId)
        return true
    end
    return false
end
function exists(dfg::CloudGraphsDFG, node::N) where N <: DFGNode
    return exists(dfg, node.label)
end

"""
    $SIGNATURES

Return whether `sym::Symbol` represents a variable vertex in the graph.
"""
isVariable(dfg::CloudGraphsDFG, sym::Symbol)::Bool =
    "VARIABLE" in _getNodeTags(dfg.neo4jInstance, [dfg.userId, dfg.robotId, dfg.sessionId, String(sym)])

"""
    $SIGNATURES

Return whether `sym::Symbol` represents a factor vertex in the graph.
"""
isFactor(dfg::CloudGraphsDFG, sym::Symbol)::Bool =
    "FACTOR" in _getNodeTags(dfg.neo4jInstance, [dfg.userId, dfg.robotId, dfg.sessionId, String(sym)])

"""
    $(SIGNATURES)
Add a DFGVariable to a DFG.
"""
function addVariable!(dfg::CloudGraphsDFG, variable::DFGVariable)::Bool
    if exists(dfg, variable)
        error("Variable '$(variable.label)' already exists in the factor graph")
    end
    props = packVariable(dfg, variable)

    neo4jNode = Neo4j.createnode(dfg.neo4jInstance.graph, props);
    variable._internalId = neo4jNode.id
    Neo4j.updatenodelabels(neo4jNode, union([string(variable.label), "VARIABLE", dfg.userId, dfg.robotId, dfg.sessionId], variable.tags))

    # Make sure that if there exists a SESSION sentinel that it is attached.
    # TODO: Optimize this.
    _bindSessionNodeToInitialVariable(dfg.neo4jInstance, dfg.userId, dfg.robotId, dfg.sessionId, string(variable.label))

    # Update our internal dictionaries.
    push!(dfg.labelDict, variable.label=>variable._internalId)
    push!(dfg.variableCache, variable.label=>variable)
    # Track insertion
    push!(dfg.addHistory, variable.label)

    return true
end

"""
    $(SIGNATURES)
Add a DFGFactor to a DFG.
"""
function addFactor!(dfg::CloudGraphsDFG, variables::Vector{DFGVariable}, factor::DFGFactor)::Bool
    if exists(dfg, factor)
        error("Factor '$(factor.label)' already exists in the factor graph")
    end

    # Update the variable ordering
    factor._variableOrderSymbols = map(v->v.label, variables)

    # Construct the properties to save
    props = packFactor(dfg, factor)

    neo4jNode = Neo4j.createnode(dfg.neo4jInstance.graph, props);
    factor._internalId = neo4jNode.id
    Neo4j.updatenodelabels(neo4jNode, union([string(factor.label), "FACTOR", dfg.userId, dfg.robotId, dfg.sessionId], factor.tags))

    # Add all the relationships - get them to cache them + make sure the links are correct
    for variable in variables
        v = getVariable(dfg, variable.label)
        vNode = Neo4j.getnode(dfg.neo4jInstance.graph, v._internalId)
        Neo4j.createrel(neo4jNode, vNode, "FACTORGRAPH")
    end

    # Graphs.add_vertex!(dfg.g, v)
    push!(dfg.labelDict, factor.label=>factor._internalId)
    push!(dfg.factorCache, factor.label=>factor)
    # Track insertion only for variables
    # push!(dfg.addHistory, factor.label

    return true
end

"""
    $(SIGNATURES)
Add a DFGFactor to a DFG.
"""
function addFactor!(dfg::CloudGraphsDFG, variableIds::Vector{Symbol}, factor::DFGFactor)::Bool
    variables = map(vId -> getVariable(dfg, vId), variableIds)
    return addFactor!(dfg, variables, factor)
end

"""
    $(SIGNATURES)
Get a DFGVariable from a DFG using its underlying integer ID.
"""
function getVariable(dfg::CloudGraphsDFG, variableId::Int64)::DFGVariable
    props = getnodeproperties(dfg.neo4jInstance.graph, variableId)
    variable = unpackVariable(dfg, props)
    variable._internalId = variableId

    # Add to cache
    push!(dfg.variableCache, variable.label=>variable)

    return variable
end


"""
    $(SIGNATURES)
Get a DFGVariable from a DFG using its label.
"""
function getVariable(dfg::CloudGraphsDFG, label::Union{Symbol, String})::DFGVariable
    if typeof(label) == String
        label = Symbol(label)
    end
    dfg.useCache && haskey(dfg.variableCache, label) && return dfg.variableCache[label]
    # Else try get it
    nodeId = _tryGetNeoNodeIdFromNodeLabel(dfg.neo4jInstance, dfg.userId, dfg.robotId, dfg.sessionId, label)
    if nodeId == nothing
        error("Unable to retrieve the ID for variable '$label'. Please check your connection to the database and that the variable exists.")
    end

    return getVariable(dfg, nodeId)
end

"""
    $(SIGNATURES)
Get a DFGFactor from a DFG using its underlying integer ID.
"""
function getFactor(dfg::CloudGraphsDFG, factorId::Int64)::DFGFactor
    props = getnodeproperties(dfg.neo4jInstance.graph, factorId)
    factor = unpackFactor(dfg, props, getSerializationModule(dfg))
    factor._internalId = factorId

    # Lastly, rebuild the metadata
    factor = dfg.rebuildFactorMetadata!(dfg, factor)
    # GUARANTEED never to bite us in the future...
    # ... TODO: refactor if changed: https://github.com/JuliaRobotics/IncrementalInference.jl/issues/350
    solverData(factor).fncargvID = factor._variableOrderSymbols

    # Add to cache
    push!(dfg.factorCache, factor.label=>factor)

    return factor
end

"""
    $(SIGNATURES)
Get a DFGFactor from a DFG using its label.
"""
function getFactor(dfg::CloudGraphsDFG, label::Union{Symbol, String})::DFGFactor
    if typeof(label) == String
        label = Symbol(label)
    end
    dfg.useCache && haskey(dfg.factorCache, label) && return dfg.factorCache[label]
    # Else try get it
    nodeId = _tryGetNeoNodeIdFromNodeLabel(dfg.neo4jInstance, dfg.userId, dfg.robotId, dfg.sessionId, label)
    if nodeId == nothing
        error("Unable to retrieve the ID for factor '$label'. Please check your connection to the database and that the factor exists.")
    end

    return getFactor(dfg, nodeId)
end

"""
    $(SIGNATURES)
Update a complete DFGVariable in the DFG.
"""
function updateVariable!(dfg::CloudGraphsDFG, variable::DFGVariable)::DFGVariable
    if !exists(dfg, variable)
        error("Variable label '$(variable.label)' does not exist in the factor graph")
    end
    nodeId = _tryGetNeoNodeIdFromNodeLabel(dfg.neo4jInstance, dfg.userId, dfg.robotId, dfg.sessionId, variable.label)
    # Update the node ID
    variable._internalId = nodeId

    neo4jNode = Neo4j.getnode(dfg.neo4jInstance.graph, nodeId)
    props = packVariable(dfg, variable)

    Neo4j.updatenodeproperties(neo4jNode, props)
    Neo4j.updatenodelabels(neo4jNode, union([string(variable.label), "VARIABLE", dfg.userId, dfg.robotId, dfg.sessionId], variable.tags))
    return variable
end

"""
    $(SIGNATURES)
Update solver and estimate data for a variable (variable can be from another graph).
"""
function mergeUpdateVariableSolverData!(dfg::CloudGraphsDFG, sourceVariable::DFGVariable)::DFGVariable
    if !exists(dfg, sourceVariable)
        error("Source variable '$(sourceVariable.label)' doesn't exist in the graph.")
    end
    var = getVariable(dfg, sourceVariable.label)
    newEsts = merge!(var.estimateDict, deepcopy(sourceVariable.estimateDict))
    newSolveData = merge!(var.solverDataDict, sourceVariable.solverDataDict)
    Neo4j.setnodeproperty(dfg.neo4jInstance.graph, var._internalId, "estimateDict",
        JSON2.write(newEsts))
    Neo4j.setnodeproperty(dfg.neo4jInstance.graph, var._internalId, "solverDataDict",
        JSON2.write(Dict(keys(newSolveData) .=> map(vnd -> pack(dfg, vnd), values(newSolveData)))))
    return sourceVariable
end

"""
    $(SIGNATURES)
Update a complete DFGFactor in the DFG.
"""
function updateFactor!(dfg::CloudGraphsDFG, factor::DFGFactor)::DFGFactor
    if !exists(dfg, factor)
        error("Factor label '$(factor.label)' does not exist in the factor graph")
    end
    nodeId = _tryGetNeoNodeIdFromNodeLabel(dfg.neo4jInstance, dfg.userId, dfg.robotId, dfg.sessionId, factor.label)
    # Update the _internalId
    factor._internalId = nodeId
    neo4jNode = Neo4j.getnode(dfg.neo4jInstance.graph, nodeId)
    props = packFactor(dfg, factor)

    Neo4j.updatenodeproperties(neo4jNode, props)
    Neo4j.updatenodelabels(neo4jNode, union([string(factor.label), "FACTOR", dfg.userId, dfg.robotId, dfg.sessionId], factor.tags))

    return factor
end


"""
    $(SIGNATURES)
Update a complete DFGFactor in the DFG and update its relationships.
"""
function updateFactor!(dfg::CloudGraphsDFG, variables::Vector{DFGVariable}, factor::DFGFactor)::DFGFactor
    # Update the body
    factor = updateFactor!(dfg, factor)

    # Now update the relationships
    existingNeighbors = getNeighbors(dfg, factor)
    if symdiff(existingNeighbors, map(v->v.label, variables)) == []
        # Done, otherwise we need to remake the edges.
        return factor
    end
    # Delete existing relationships
    fNode = Neo4j.getnode(dfg.neo4jInstance.graph, factor._internalId)
    for relationship in Neo4j.getrels(fNode)
        if relationship.reltype == "FACTORGRAPH"
            Neo4j.deleterel(relationship)
        end
    end
    # Make new ones
    for variable in variables
        v = getVariable(dfg, variable.label)
        vNode = Neo4j.getnode(dfg.neo4jInstance.graph, v._internalId)
        @info "Creating REL between factor $(fNode) and variable $(vNode)"
        Neo4j.createrel(fNode, vNode, "FACTORGRAPH")
    end

    return factor
end

"""
    $(SIGNATURES)
Update a complete DFGFactor in the DFG and update it's relationships.
"""
function updateFactor!(dfg::CloudGraphsDFG, variableIds::Vector{Symbol}, factor::DFGFactor)::DFGFactor
    variables = map(vId -> getVariable(dfg, vId), variableIds)
    return updateFactor!(dfg, variables, factor)
end

"""
    $(SIGNATURES)
Delete a DFGVariable from the DFG using its label.
"""
function deleteVariable!(dfg::CloudGraphsDFG, label::Symbol)::DFGVariable
    variable = nothing
    if dfg.useCache && haskey(dfg.variableCache, label)
        variable = dfg.variableCache[label]
    else
        # Else try get it
        variable = getVariable(dfg, label)
    end
    if variable == nothing
        error("Unable to retrieve the ID for variable '$label'. Please check your connection to the database and that the variable exists.")
    end

    # Perform detach+deletion
    _getNeoNodesFromCyphonQuery(dfg.neo4jInstance, "(node:VARIABLE) where id(node)=$(variable._internalId) detach delete node ")

    # Clearing history
    dfg.addHistory = symdiff(dfg.addHistory, [label])
    haskey(dfg.variableCache, label) && delete!(dfg.variableCache, label)
    haskey(dfg.labelDict, label) && delete!(dfg.labelDict, label)
    return variable
end

#Alias
"""
    $(SIGNATURES)
Delete a referenced DFGVariable from the DFG.
"""
deleteVariable!(dfg::CloudGraphsDFG, variable::DFGVariable)::DFGVariable = deleteVariable!(dfg, variable.label)

"""
    $(SIGNATURES)
Delete a DFGFactor from the DFG using its label.
"""
function deleteFactor!(dfg::CloudGraphsDFG, label::Symbol)::DFGFactor
    factor = nothing
    if dfg.useCache && haskey(dfg.factoreCache, label)
        factor = dfg.factorCache[label]
    else
        # Else try get it
        factor = getFactor(dfg, label)
    end
    if factor == nothing
        error("Unable to retrieve the ID for factor '$label'. Please check your connection to the database and that the factor exists.")
    end

    # Perform detach+deletion
    _getNeoNodesFromCyphonQuery(dfg.neo4jInstance, "(node:FACTOR) where id(node)=$(factor._internalId) detach delete node ")

    # Clearing history
    dfg.addHistory = symdiff(dfg.addHistory, [label])
    haskey(dfg.factorCache, label) && delete!(dfg.factorCache, label)
    haskey(dfg.labelDict, label) && delete!(dfg.labelDict, label)
    return factor
end

# Alias
"""
    $(SIGNATURES)
Delete the referened DFGFactor from the DFG.
"""
deleteFactor!(dfg::CloudGraphsDFG, factor::DFGFactor)::DFGFactor = deleteFactor!(dfg, factor.label)

"""
    $(SIGNATURES)
List the DFGVariables in the DFG.
Optionally specify a label regular expression to retrieves a subset of the variables.
"""
function getVariables(dfg::CloudGraphsDFG, regexFilter::Union{Nothing, Regex}=nothing; tags::Vector{Symbol}=Symbol[])::Vector{DFGVariable}
    variableIds = getVariableIds(dfg, regexFilter)
    # TODO: Optimize to use tags in query here!
    variables = map(vId->getVariable(dfg, vId), variableIds)
    if length(tags) > 0
        mask = map(v -> length(intersect(v.tags, tags)) > 0, variables )
        return variables[mask]
    end
    return variables
end

"""
    $(SIGNATURES)
Get a list of IDs of the DFGVariables in the DFG.
Optionally specify a label regular expression to retrieves a subset of the variables.
"""
function getVariableIds(dfg::CloudGraphsDFG, regexFilter::Union{Nothing, Regex}=nothing)::Vector{Symbol}
    # Optimized for DB call
    if regexFilter == nothing
        return _getLabelsFromCyphonQuery(dfg.neo4jInstance, "(node:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId):VARIABLE)")
    else
        return _getLabelsFromCyphonQuery(dfg.neo4jInstance, "(node:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId):VARIABLE) where node.label =~ '$(regexFilter.pattern)'")
    end
end

# Alias
"""
    $(SIGNATURES)
List the DFGVariables in the DFG.
Optionally specify a label regular expression to retrieves a subset of the variables.
"""
ls(dfg::CloudGraphsDFG, regexFilter::Union{Nothing, Regex}=nothing)::Vector{Symbol} = getVariableIds(dfg, regexFilter)

"""
    $(SIGNATURES)
List the DFGFactors in the DFG.
Optionally specify a label regular expression to retrieves a subset of the factors.
"""
function getFactors(dfg::CloudGraphsDFG, regexFilter::Union{Nothing, Regex}=nothing)::Vector{DFGFactor}
    factorIds = getFactorIds(dfg, regexFilter)
    return map(vId->getFactor(dfg, vId), factorIds)
end

"""
    $(SIGNATURES)
Get a list of the IDs of the DFGFactors in the DFG.
Optionally specify a label regular expression to retrieves a subset of the factors.
"""
function getFactorIds(dfg::CloudGraphsDFG, regexFilter::Union{Nothing, Regex}=nothing)::Vector{Symbol}
    # Optimized for DB call
    if regexFilter == nothing
        return _getLabelsFromCyphonQuery(dfg.neo4jInstance, "(node:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId):FACTOR)")
    else
        return _getLabelsFromCyphonQuery(dfg.neo4jInstance, "(node:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId):FACTOR) where node.label =~ '$(regexFilter.pattern)'")
    end
end

# Alias
"""
    $(SIGNATURES)
List the DFGFactors in the DFG.
Optionally specify a label regular expression to retrieves a subset of the factors.
"""
lsf(dfg::CloudGraphsDFG, regexFilter::Union{Nothing, Regex}=nothing)::Vector{Symbol} = getFactorIds(dfg, regexFilter)

# Alias - getNeighbors
"""
    $(SIGNATURES)
Get neighbors around a given node. TODO: Refactor this
"""
function lsf(dfg::CloudGraphsDFG, label::Symbol)::Vector{Symbol}
  return getNeighbors(dfg, label)
end

"""
    $(SIGNATURES)
Checks if the graph is fully connected, returns true if so.
"""
function isFullyConnected(dfg::CloudGraphsDFG)::Bool
    # If the total number of nodes == total number of distinct connected nodes, then it is fully connected
    # Total nodes
    varIds = getVariableIds(dfg)
    factIds = getFactorIds(dfg)
    length(varIds) + length(factIds) == 0 && return false

    # Total connected nodes - thank you Neo4j for 0..* awesomeness!!
    query = """
        match (n:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId):$(varIds[1]))-[FACTORGRAPH*]-(node:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId))
        WHERE (n:VARIABLE OR n:FACTOR OR node:VARIABLE OR node:FACTOR) and not (node:SESSION)
        WITH collect(n)+collect(node) as nodelist
        unwind nodelist as nodes
        return count(distinct nodes)"""
    @debug "[Querying] $query"
    result = _queryNeo4j(dfg.neo4jInstance, query)
    # Neo4j.jl data structure sometimes feels brittle... like below
    return result.results[1]["data"][1]["row"][1] == length(varIds) + length(factIds)
end

#Alias
"""
    $(SIGNATURES)
Checks if the graph is not fully connected, returns true if it is not contiguous.
"""
hasOrphans(dfg::CloudGraphsDFG)::Bool = !isFullyConnected(dfg)

"""
    $(SIGNATURES)
Retrieve a list of labels of the immediate neighbors around a given variable or factor.
"""
function getNeighbors(dfg::CloudGraphsDFG, node::T; ready::Union{Nothing, Int}=nothing)::Vector{Symbol}  where T <: DFGNode
    query = "(n:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId):$(node.label))--(node) where (node:VARIABLE or node:FACTOR) "
    if ready != nothing
        query = query * " and node.ready >= $(ready)"
    end
    @debug "[Query] $query"
    neighbors = _getLabelsFromCyphonQuery(dfg.neo4jInstance, query)
    # If factor, need to do variable ordering
    if T <: DFGFactor
        neighbors = intersect(node._variableOrderSymbols, neighbors)
    end
    return neighbors
end

"""
    $(SIGNATURES)
Retrieve a list of labels of the immediate neighbors around a given variable or factor specified by its label.
"""
function getNeighbors(dfg::CloudGraphsDFG, label::Symbol; ready::Union{Nothing, Int}=nothing)::Vector{Symbol}
    query = "(n:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId):$(label))--(node) where (node:VARIABLE or node:FACTOR) "
    if ready != nothing
        query = query * " and node.ready >= $(ready)"
    end
    @debug "[Query] $query"
    neighbors = _getLabelsFromCyphonQuery(dfg.neo4jInstance, query)
    # If factor, need to do variable ordering
    if isFactor(dfg, label)
        # Server is authority
        serverOrder = Symbol.(JSON2.read(_getNodeProperty(dfg.neo4jInstance, [dfg.userId, dfg.robotId, dfg.sessionId, String(label)], "_variableOrderSymbols")))
        neighbors = intersect(serverOrder, neighbors)
    end
    return neighbors
end

# Aliases
"""
    $(SIGNATURES)
Retrieve a list of labels of the immediate neighbors around a given variable or factor.
"""
function ls(dfg::CloudGraphsDFG, node::T)::Vector{Symbol} where T <: DFGNode
    return getNeighbors(dfg, node)
end
"""
    $(SIGNATURES)
Retrieve a list of labels of the immediate neighbors around a given variable or factor specified by its label.
"""
function ls(dfg::CloudGraphsDFG, label::Symbol)::Vector{Symbol} where T <: DFGNode
    return getNeighbors(dfg, label)
end

## This is moved to services/AbstractDFG.jl
# function _copyIntoGraph!(sourceDFG::CloudGraphsDFG, destDFG::CloudGraphsDFG, variableFactorLabels::Vector{Symbol}, includeOrphanFactors::Bool=false)::Nothing

"""
    $(SIGNATURES)
Retrieve a deep subgraph copy around a given variable or factor.
Optionally provide a distance to specify the number of edges should be followed.
Optionally provide an existing subgraph addToDFG, the extracted nodes will be copied into this graph. By default a new subgraph will be created.
Note: By default orphaned factors (where the subgraph does not contain all the related variables) are not returned. Set includeOrphanFactors to return the orphans irrespective of whether the subgraph contains all the variables.
"""
function getSubgraphAroundNode(dfg::CloudGraphsDFG, node::DFGNode, distance::Int64=1, includeOrphanFactors::Bool=false, addToDFG::AbstractDFG=_getDuplicatedEmptyDFG(dfg); solvable::Int=0)::AbstractDFG
    distance < 1 && error("getSubgraphAroundNode() only works for distance > 0")

    # Thank you Neo4j for 0..* awesomeness!!
    neighborList = _getLabelsFromCyphonQuery(dfg.neo4jInstance,
        "(n:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId):$(node.label))-[FACTORGRAPH*0..$distance]-(node:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId)) WHERE (n:VARIABLE OR n:FACTOR OR node:VARIABLE OR node:FACTOR) and not (node:SESSION) and (node.solvable >= $solvable)")

    # Copy the section of graph we want
    _copyIntoGraph!(dfg, addToDFG, neighborList, includeOrphanFactors)
    return addToDFG
end


"""
    $(SIGNATURES)
Get a deep subgraph copy from the DFG given a list of variables and factors.
Optionally provide an existing subgraph addToDFG, the extracted nodes will be copied into this graph. By default a new subgraph will be created.
Note: By default orphaned factors (where the subgraph does not contain all the related variables) are not returned. Set includeOrphanFactors to return the orphans irrespective of whether the subgraph contains all the variables.
"""
function getSubgraph(dfg::CloudGraphsDFG,
                     variableFactorLabels::Vector{Symbol},
                     includeOrphanFactors::Bool=false,
                     addToDFG::G=_getDuplicatedEmptyDFG(dfg) )::G where {G <: AbstractDFG}
    # Making a copy session if not specified

    _copyIntoGraph!(dfg, addToDFG, variableFactorLabels, includeOrphanFactors)

    return addToDFG
end

"""
    $(SIGNATURES)
Get an adjacency matrix for the DFG, returned as a Matrix{Union{Nothing, Symbol}}.
Rows are all factors, columns are all variables, and each cell contains either nothing or the symbol of the relating factor.
The first row and first column are factor and variable headings respectively.
This is optimized for database usage.
"""
function getAdjacencyMatrix(dfg::CloudGraphsDFG)::Matrix{Union{Nothing, Symbol}}
    varLabels = sort(getVariableIds(dfg))
    factLabels = sort(getFactorIds(dfg))
    vDict = Dict(varLabels .=> [1:length(varLabels)...].+1)
    fDict = Dict(factLabels .=> [1:length(factLabels)...].+1)

    adjMat = Matrix{Union{Nothing, Symbol}}(nothing, length(factLabels)+1, length(varLabels)+1)
    # Set row/col headings
    adjMat[2:end, 1] = factLabels
    adjMat[1, 2:end] = varLabels

    # Now ask for all relationships for this session graph
    loadtx = transaction(dfg.neo4jInstance.connection)
    query = "START n=node(*) MATCH (n:VARIABLE:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId))-[r:FACTORGRAPH]-(m:FACTOR:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId)) RETURN n.label as variable, m.label as factor;"
    nodes = loadtx(query; submit=true)
    # Have to finish the transaction
    commit(loadtx)
    if length(nodes.errors) > 0
        error(string(nodes.errors))
    end
    # Add in the relationships
    varRel = Symbol.(map(node -> node["row"][1], nodes.results[1]["data"]))
    factRel = Symbol.(map(node -> node["row"][2], nodes.results[1]["data"]))
    for i = 1:length(varRel)
        adjMat[fDict[factRel[i]], vDict[varRel[i]]] = factRel[i]
    end

    return adjMat
end

function getAdjacencyMatrixSparse(dfg::CloudGraphsDFG)::Tuple{SparseMatrixCSC, Vector{Symbol}, Vector{Symbol}}
    varLabels = getVariableIds(dfg)
    factLabels = getFactorIds(dfg)
    vDict = Dict(varLabels .=> [1:length(varLabels)...])
    fDict = Dict(factLabels .=> [1:length(factLabels)...])

    adjMat = spzeros(Int, length(factLabels), length(varLabels))

    # Now ask for all relationships for this session graph
    loadtx = transaction(dfg.neo4jInstance.connection)
    query = "START n=node(*) MATCH (n:VARIABLE:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId))-[r:FACTORGRAPH]-(m:FACTOR:$(dfg.userId):$(dfg.robotId):$(dfg.sessionId)) RETURN n.label as variable, m.label as factor;"
    nodes = loadtx(query; submit=true)
    # Have to finish the transaction
    commit(loadtx)
    if length(nodes.errors) > 0
        error(string(nodes.errors))
    end
    # Add in the relationships
    varRel = Symbol.(map(node -> node["row"][1], nodes.results[1]["data"]))
    factRel = Symbol.(map(node -> node["row"][2], nodes.results[1]["data"]))
    for i = 1:length(varRel)
        adjMat[fDict[factRel[i]], vDict[varRel[i]]] = 1
    end

    return adjMat, varLabels, factLabels
end
