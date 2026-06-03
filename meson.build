project('wl-vapi-gen', ['c', 'vala'],
    version: '2.0.0',
)

version = meson.project_version()
version_split = version.split('.')

config = configure_file(
  input: 'src/config.vala.in',
  output: 'config.vala',
  configuration: {
    'VERSION': version,
    'MAJOR_VERSION': version_split[0],
    'MINOR_VERSION': version_split[1],
    'MICRO_VERSION': version_split[2],
  },
)

sources = [config] + [
  'src/protocol.vala',
  'src/utils.vala'
]

deps = [
    dependency('libxml-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gio-2.0'),
    dependency('gee-0.8')
]

wl_vapi_gen = executable('wl-vapi-gen',
    'src/wl-vapi-gen.vala',
    sources,
    dependencies: deps,
    install: true,
)
wl_vala_gen = executable('wl-vala-gen',
    'src/wl-vala-gen.vala',
    sources,
    dependencies: deps,
    install: true,
)

if meson.is_subproject()
  meson.override_find_program('wl-vapi-gen', wl_vapi_gen)
  meson.override_find_program('wl-vala-gen', wl_vala_gen)
endif

