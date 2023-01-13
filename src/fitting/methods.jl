export wrap_model, wrap_model_noflux
export AbstractFittingAlgorithm, LevenbergMarquadt, fit

abstract type AbstractFittingAlgorithm end

function fit(::FittingProblem, alg::AbstractFittingAlgorithm; _...)
    error("Algorithm `$(typeof(alg).name.name)` not implemented.")
end

struct LevenbergMarquadt{T} <: AbstractFittingAlgorithm
    λ_inc::T
    λ_dec::T
end
LevenbergMarquadt(; λ_inc = 10.0, λ_dec = 0.1) = LevenbergMarquadt(λ_inc, λ_dec)

function _lazy_folded_invokemodel(
    model::AbstractSpectralModel,
    data::AbstractSpectralDataset,
)
    ΔE = data.energy_bin_widths
    # pre-mask the response matrix to ensure channel out corresponds to the active data points
    R = fold_ancillary(data)[data.mask, :]
    # pre-allocate the output 
    wrapped = (energy, params) -> begin
        flux = invokemodel(energy, model, params)
        flux = (R * flux)
        @. flux = flux / ΔE
    end
    wrapped
end

function fit(
    prob::FittingProblem,
    alg::LevenbergMarquadt;
    verbose = false,
    max_iter = 1000,
    kwargs...,
)
    if model_count(prob) == 1 && data_count(prob) == 1
        let model = prob.model.m[1], data = prob.data.d[1]
            f = _lazy_folded_invokemodel(model, data)
            x = energy_vector(data)
            y = data.rate
            cov = 1 ./ data.rateerror .^ 2
            parameters = modelparameters(model)
            lsq_result = LsqFit.curve_fit(
                f,
                x,
                y,
                cov,
                get_value.(parameters);
                lower = get_lowerlimit.(parameters),
                upper = get_upperlimit.(parameters),
                lambda_increase = alg.λ_inc,
                lambda_decrease = alg.λ_dec,
                show_trace = verbose,
                autodiff = implementation(model) isa JuliaImplementation ? :forward :
                           :finite,
                maxIter = max_iter,
                kwargs...,
            )
            unpack_lsqfit_result(lsq_result, model, f, x, y, data.rateerror .^ 2)
        end
    end
end

function wrap_model(
    model::AbstractSpectralModel,
    data::SpectralDataset{T};
    energy = energy_vector(data),
) where {T}
    fluxes = make_fluxes(energy, flux_count(model), T)
    frozen_params = get_value.(frozenparameters(model))
    ΔE = data.energy_bin_widths
    # pre-mask the response matrix to ensure channel out corresponds to the active data points
    R = fold_ancillary(data)[data.mask, :]
    # pre-allocate the output 
    outflux = zeros(T, length(ΔE))
    wrapped =
        (energy, params) -> begin
            invokemodel!(fluxes, energy, model, params, frozen_params)
            mul!(outflux, R, fluxes[1])
            @. outflux = outflux / ΔE
        end
    energy, wrapped
end

function wrap_model_noflux(
    model::AbstractSpectralModel,
    data::SpectralDataset{T};
    energy = energy_vector(data),
) where {T}
    ΔE = data.energy_bin_widths
    # pre-mask the response matrix to ensure channel out corresponds to the active data points
    R = fold_ancillary(data)[data.mask, :]
    # pre-allocate the output 
    wrapped = (energy, params) -> begin
        flux = invokemodel(energy, model, params)
        flux = (R * flux)
        @. flux = flux / ΔE
    end
    energy, wrapped
end

function wrap_Optimization(
    model::AbstractSpectralModel,
    data::SpectralDataset{T};
    energy = energy_vector(data),
    target = data.rate,
    variance = data.rateerror .^ 2,
) where {T}
    ΔE = data.energy_bin_widths
    # pre-mask the response matrix to ensure channel out corresponds to the active data points
    R = fold_ancillary(data)[data.mask, :]
    n = length(target)
    # pre-allocate the output 
    wrapped = (params, energy) -> begin
        flux = invokemodel(energy, model, params)
        flux = (R * flux)
        @. flux = flux / ΔE
        χ2_from_ŷyvar(flux, target, variance)
        # l = @. flux - target + target * ( log(target) - log(flux) )
        # -l
        # l, flux
    end
    energy, wrapped
end

χ2_from_ŷyvar(ŷ, y, variance) = sum(@.((y - ŷ)^2 / variance))

function χ2(model::Function, params, data::SpectralDataset; energy = energy_vector(data))
    ŷ = model(energy, params)
    χ2_from_ŷyvar(ŷ, data.rate, data.rateerror .^ 2)
end