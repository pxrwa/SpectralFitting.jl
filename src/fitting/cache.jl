abstract type AbstractFittingCache end

_invoke_and_transform!(cache::AbstractFittingCache, domain, params) =
    error("Not implemented for $(typeof(cache))")

# one of these for each (mulit)model / data pair
struct SpectralCache{M,O,T,P,TransformerType} <: AbstractFittingCache
    model::M
    model_output::O
    calculated_objective::T
    parameter_cache::P
    transfomer!!::TransformerType
    function SpectralCache(
        layout::AbstractDataLayout,
        model::M,
        domain,
        objective,
        transformer::XfmT;
        param_diff_cache_size = nothing,
    ) where {M,XfmT}
        model_output = DiffCache(construct_objective_cache(layout, model, domain))
        calc_obj = similar(objective)
        calc_obj .= 0
        calc_obj_cache = DiffCache(calc_obj)
        param_cache =
            make_diff_parameter_cache(model; param_diff_cache_size = param_diff_cache_size)
        new{M,typeof(model_output),typeof(calc_obj_cache),typeof(param_cache),XfmT}(
            model,
            model_output,
            calc_obj_cache,
            param_cache,
            transformer,
        )
    end
end

function Base.show(io::IO, @nospecialize(config::SpectralCache{M})) where {M}
    descr = "SpectralCache{$(Base.typename(M).name)}"
    print(io, descr)
end

function Base.show(
    io::IO,
    ::MIME"text/plain",
    @nospecialize(config::SpectralCache{M})
) where {M}
    descr = "SpectralCache{$(Base.typename(M).name)}"
    print(io, descr)
end

function _invoke_and_transform!(cache::SpectralCache, domain, params)
    # read all caches
    model_output = get_tmp(cache.model_output, params)
    calc_obj = get_tmp(cache.calculated_objective, params)

    # update the free parameters, and then get all of them
    update_free_parameters!(cache.parameter_cache, params)
    parameters = _get_parameters(cache.parameter_cache, params)

    output = invokemodel!(model_output, domain, cache.model, parameters)
    cache.transfomer!!(calc_obj, domain, output)

    calc_obj
end

struct FittingConfig{ImplType,CacheType,P,D,O}
    cache::CacheType
    parameters::P
    domain::D
    objective::O
    variance::O
    covariance::O
    function FittingConfig(
        impl::AbstractSpectralModelImplementation,
        cache::C,
        params::P,
        domain::D,
        objective::O,
        variance::O;
        covariance::O = inv.(variance),
    ) where {C,P,D,O}
        new{typeof(impl),C,P,D,O}(cache, params, domain, objective, variance, covariance)
    end
end

function FittingConfig(model::AbstractSpectralModel, dataset::AbstractDataset)
    layout = common_support(model, dataset)
    domain = make_model_domain(layout, dataset)
    objective = make_objective(layout, dataset)
    variance = make_objective_variance(layout, dataset)
    params = _allocate_free_parameters(model)
    cache = SpectralCache(
        layout,
        model,
        domain,
        objective,
        objective_transformer(layout, dataset),
    )
    FittingConfig(implementation(model), cache, params, domain, objective, variance)
end

function _f_objective(config::FittingConfig)
    function f!!(domain, parameters)
        _invoke_and_transform!(config.cache, domain, parameters)
    end
end

function finalize(config::FittingConfig, params; statistic = ChiSquared())
    y = _f_objective(config)(config.domain, params)
    chi2 = measure(statistic, config.objective, y, config.variance)
    FittingResult(chi2, params, config)
end

supports_autodiff(config::FittingConfig{<:JuliaImplementation}) = true
supports_autodiff(config::FittingConfig) = false

function Base.show(io::IO, @nospecialize(config::FittingConfig))
    descr = "FittingConfig"
    print(io, descr)
end

function Base.show(io::IO, ::MIME"text/plain", @nospecialize(config::FittingConfig))
    descr = "FittingConfig"
    print(io, descr)
end

export FittingConfig
