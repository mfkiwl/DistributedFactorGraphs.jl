module GraphsDFGs

using Graphs
using DocStringExtensions
using UUIDs

using ...DistributedFactorGraphs

# import ...DistributedFactorGraphs: AbstractDFG, DFGNode, AbstractDFGVariable, AbstractDFGFactor, DFGSummary, AbstractParams, NoSolverParams, DFGVariable, DFGFactor

# import DFG functions to extend
import ...DistributedFactorGraphs:  setSolverParams!,
                                    getFactor,
                                    setDescription!,
                                    # getLabelDict,
                                    getUserData,
                                    setUserData!,
                                    getRobotData,
                                    setRobotData!,
                                    getSessionData,
                                    setSessionData!,
                                    addVariable!,
                                    getVariable,
                                    getAddHistory,
                                    addFactor!,
                                    getSolverParams,
                                    exists,
                                    isVariable,
                                    isFactor,
                                    getDescription,
                                    updateVariable!,
                                    updateFactor!,
                                    deleteVariable!,
                                    deleteFactor!,
                                    getVariables,
                                    listVariables,
                                    ls,
                                    getFactors,
                                    listFactors,
                                    lsf,
                                    isConnected,
                                    getNeighbors,
                                    buildSubgraph,
                                    copyGraph!,
                                    getBiadjacencyMatrix,
                                    _getDuplicatedEmptyDFG,
                                    toDot,
                                    toDotFile,
                                    findShortestPathDijkstra

include("FactorGraphs/FactorGraphs.jl")
using .FactorGraphs

# export SymbolEdge, is_directed, has_edge
# Imports
include("entities/GraphsDFG.jl")
include("services/GraphsDFG.jl")

# Exports
export GraphsDFG


end
