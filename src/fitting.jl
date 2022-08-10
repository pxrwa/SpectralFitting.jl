export fitparams!

function fitparams!(
    params,
    model,
    dataset::SpectralDataset,
    energy = get_energy_bins(dataset.response);
    kwargs...,
)
    __fitparams!(
        params,
        model,
        dataset.response,
        dataset.counts,
        dataset.countserror,
        energy,
        dataset.channels;
        kwargs...,
    )
end

function __fitparams!(
    params,
    model::M,
    rm::ResponseMatrix,
    target,
    error_target,
    energy,
    channels;
    kwargs...,
) where {M<:AbstractSpectralModel}

    p0 = get_value.(params)
    lb = get_lowerlimit.(params)
    ub = get_upperlimit.(params)

    fit =
        __lsq_fit(implementation(M), model, p0, lb, ub, rm, target, error_target, energy, channels; kwargs...)

    means = LsqFit.coef(fit)
    errs = LsqFit.stderror(fit)

    for (p, m, e) in zip(params, means, errs)
        set_value!(p, m)
        set_error!(p, e)
    end

    fit
end

function __lsq_fit(::AbstractSpectralModelImplementation, model, p0, lb, ub, rm, target, error_target, energy, channels; kwargs...)
    frozen_p = get_value.(get_frozen_model_params(model))
    fluxes = make_fluxes(energy, flux_count(model))
    foldedmodel(x, p) =
        @views fold_response(invokemodel!(fluxes, x, model, p, frozen_p), x, rm)[channels]

    # seems to cause nans and infs
    cov_err = @. 1 / (error_target ^ 2)

    fit = LsqFit.curve_fit(
        foldedmodel,
        energy,
        target,
        cov_err,
        p0;
        lower = lb,
        upper = ub,
        kwargs...,
    )
    fit
end

# function __lsq_fit(::JuliaImplementation, model, p0, lb, ub, rm, target, error_target, energy, channels; kwargs...)
#     frozen_p = get_value.(get_frozen_model_params(model))
#     d_fluxes = make_dual_fluxes(energy, flux_count(model))
#     foldedmodel(x, p) = begin
#         fluxes = map(i -> get_tmp(i, p[1]), d_fluxes)
#         @views fold_response(invokemodel!(fluxes, x, model, p, frozen_p), x, rm)[channels]
#     end

#     # seems to cause nans and infs
#     cov_err = 1 ./ (error_target .^ 2)

#     fit = LsqFit.curve_fit(
#         foldedmodel,
#         energy,
#         target,
#         cov_err,
#         p0;
#         lower = lb,
#         upper = ub,
#         autodiff = :forwarddiff,
#         kwargs...,
#     )
#     fit
# end