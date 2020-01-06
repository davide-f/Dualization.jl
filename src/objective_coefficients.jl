"""
    set_dual_model_sense!(dual_model::MOI.ModelLike, model::MOI.ModelLike)

Set the dual model objective sense.
"""
function set_dual_model_sense(dual_model::MOI.ModelLike, primal_model::MOI.ModelLike)::Nothing where T
    # Get model sense
    primal_sense = MOI.get(primal_model, MOI.ObjectiveSense())
    if primal_sense == MOI.FEASIBILITY_SENSE
        error(primal_sense, " is not supported") # Feasibility should be supported?
    end
    # Set dual model sense
    dual_sense = (primal_sense == MOI.MIN_SENSE) ? MOI.MAX_SENSE : MOI.MIN_SENSE
    MOI.set(dual_model, MOI.ObjectiveSense(), dual_sense)
    return
end

# Primals
"""
    PrimalObjective{T}

Primal objective is defined as a `MOI.ScalarAffineFunction`
"""
struct PrimalObjective{T}
    saf::SAF{T}

    function PrimalObjective{T}(obj::SAF{T}) where T
        canonical_obj = MOIU.canonical(obj)
        # if isempty(canonical_obj.terms)
        #     error("Dualization does not support models with no variables in the objective function.")
        # end
        # This was commented for now, because the current understanding is that
        # problems like {min 0*x} are well defined and have well defined dual problems.
        # Therefore, they present no issue to dualization as opposed to problems
        # with FEASIBILITY_SENSE that do not have a well defined dual problem.
        # Moreover, JuMP and MOI default is FEASIBILITY_SENSE, if a MIN_SENSE
        # is in the problem, it is because the user set it explicitly.
        # For more on the original discussion, see:
        # https://github.com/JuliaOpt/Dualization.jl/pull/64#discussion_r347484642
        return new(canonical_obj)
    end
end

# Duals
"""
    DualObjective{T}

Dual objective is defined as a `MOI.ScalarAffineFunction`.
"""
struct DualObjective{T}
    saf::SAF{T}
end

function get_saf(objective::Union{PrimalObjective{T}, DualObjective{T}})::SAF{T} where T
    return objective.saf
end

"""
    get_primal_obj_coeffs(model::MOI.ModelLike)

Get the coefficients from the primal objective function and return a `PrimalObjective{T}`.
"""
function get_primal_objective(primal_model::MOI.ModelLike)
    T = MOI.get(primal_model, MOI.ObjectiveFunctionType())
    return _get_primal_objective(MOI.get(primal_model, MOI.ObjectiveFunction{T}()))
end

function _get_primal_objective(obj_fun::SAF{T}) where T
    return PrimalObjective{T}(obj_fun)
end

# Float64 is default while I don't know how to take other types
_get_primal_objective(obj_fun::SVF) = _get_primal_objective(obj_fun, Float64)
function _get_primal_objective(obj_fun::SVF, T::Type)
    return PrimalObjective{T}(SAF{T}(obj_fun))
end

# allow removing variables from objective function
function get_primal_objective(primal_model::MOI.ModelLike, variable_parameters::Vector{VI})
    p_obj = get_primal_objective(primal_model)
    # discard variable_parameters
    new_p_obj = remove_variables(p_obj, variable_parameters)
    return new_p_obj
end

function remove_variables(p_obj::PrimalObjective{T},
    variable_parameters::Vector{VI}) where T
    PrimalObjective{T}(remove_variables(p_obj.saf, variable_parameters))
end
function remove_variables(saf::MOI.ScalarAffineFunction{T},
    variable_parameters::Vector{VI}) where T
    to_delete = get_indices_variables(saf, variable_parameters)
    new_saf = deepcopy(saf)
    deleteat!(new_saf.terms, to_delete)
    return new_saf
end

function get_indices_variables(saf::MOI.ScalarAffineFunction{T},
    variable_parameters::Vector{VI}) where T
    indices = Int[]
    sizehint!(indices, min(length(variable_parameters), length(saf.terms)))
    for (ind, term) in enumerate(saf.terms)
        if term.variable_index in variable_parameters
            push!(indices, ind)
        end
    end
    return indices
end


# You can add other generic _get_primal_obj_coeffs functions here



"""
    set_dual_objective(dual_model::MOI.ModelLike, dual_objective::DualObjective{T})::Nothing where T

Add the objective function to the dual model.
"""
function set_dual_objective(dual_model::MOI.ModelLike, dual_objective::DualObjective{T})::Nothing where T
    # Set dual model objective function
    MOI.set(dual_model, MOI.ObjectiveFunction{SAF{T}}(),
            get_saf(dual_objective))
    return
end

"""
    get_dual_objective(dual_model::MOI.ModelLike, dual_obj_affine_terms::Dict,
                       primal_objective::PrimalObjective{T})::DualObjective{T} where T

build the dual model objective function from the primal model.
"""
function get_dual_objective(dual_model::MOI.ModelLike, dual_obj_affine_terms::Dict,
                            primal_objective::PrimalObjective{T})::DualObjective{T} where T

    sense = MOI.get(dual_model, MOI.ObjectiveSense()) # Get dual model sense

    num_objective_terms = length(dual_obj_affine_terms)
    term_vec = Vector{T}(undef, num_objective_terms)
    vi_vec   = Vector{VI}(undef, num_objective_terms)
    for (i, var) in enumerate(keys(dual_obj_affine_terms)) # Number of constraints of the primal model
        term = dual_obj_affine_terms[var]
        # Add positive terms bi if dual model sense is max
        term_vec[i] = (sense == MOI.MAX_SENSE ? -1 : 1) * term
        # Variable index associated with term bi
        vi_vec[i] = var
    end
    saf_dual_objective = MOI.ScalarAffineFunction(
                         MOI.ScalarAffineTerm.(term_vec,
                                               vi_vec),
                                               MOI.constant(get_saf(primal_objective)))
    return DualObjective{T}(saf_dual_objective)
end
