project('wl-vapi-gen',
  version: '0.1.0',
)

prefix = get_option('prefix')
datadir = join_paths(prefix, get_option('datadir'))

py = import('python').find_installation('python3')

# configure_file(
#   input: 'wl-vapi-gen.pc.in',
#   output: 'wl-vapi-gen.pc',
#   configuration: { 'VERSION': meson.project_version() },
#   install: not meson.is_subproject(),
#   install_dir: join_paths(datadir, 'pkgconfig'),
# )

config = configuration_data({
  'VERSION': meson.project_version(),
  'PROG_NAME': meson.project_name(),
})

wl_vapi_gen_dep = declare_dependency()
wl_vapi_gen = configure_file(
  input: 'wl-vapi-gen.py',
  output: 'wl-vapi-gen',
  configuration: config,
  install: not meson.is_subproject(),
  install_dir: get_option('bindir'),
)


pkgconf = configuration_data()
pkgconf.set('VERSION', meson.project_version())
configure_file(
  input: 'wl-vapi-gen.pc.in',
  output: 'wl-vapi-gen.pc',
  configuration: pkgconf,
  install: not meson.is_subproject(),
  install_dir: get_option('datadir') / 'pkgconfig',
)

if meson.is_subproject()
  meson.override_find_program('wl-vapi-gen', wl_vapi_gen)
endif

