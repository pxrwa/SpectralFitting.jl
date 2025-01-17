abstract type AbstractXmmNewtonDevice end
struct XmmEPIC <: AbstractXmmNewtonDevice end

struct XmmData{T,D} <: AbstractDataset
    device::D
    data::SpectralData{T}
    paths::SpectralDataPaths
    observation_id::String
    exposure_id::String
    object::String
end

function XmmData(device::AbstractXmmNewtonDevice, spec_path; T::Type = Float64, kwargs...)
    paths = SpectralDataPaths(spec_path)
    config = StandardOGIPConfig(rmf_matrix_index = 2, rmf_energy_index = 3, T = T)

    # read metadata
    fits = FITS(paths.spectrum)
    header = read_header(fits[1])
    close(fits)

    obs_id = haskey(header, "OBS_ID") ? header["OBS_ID"] : "[no observation id]"
    exposure_id = haskey(header, "EXP_ID") ? header["EXP_ID"] : "[no exposure id]"
    object = haskey(header, "OBJECT") ? header["OBJECT"] : "[no object]"

    data = SpectralData(paths, config; kwargs...)
    XmmData(device, data, paths, obs_id, exposure_id, object)
end

make_label(data::XmmData) = data.observation_id

@_forward_SpectralData_api XmmData.data

function Base.show(io::IO, @nospecialize(data::XmmData{T})) where {T}
    print(io, "XmmData[dev=$(data.device),obs_id=$(data.observation_id)]")
end

function _printinfo(io, data::XmmData{T}) where {T}
    descr = """XmmData for $(Base.typename(typeof(data.device)).name):
      . Object              : $(data.object)
      . Observation ID      : $(data.observation_id)
      . Exposure ID         : $(data.exposure_id)
    """
    print(io, descr)
    _printinfo(io, data.data)
end

export XmmData, XmmEPIC
