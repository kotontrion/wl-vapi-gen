# wl-vapi-gen

wl-vapi-gen is a tool for generating Vala bindings for Wayland protocols. After creating the C stubs for a wayland protocol using wayland-scanner, this tool can be used to generate the corresponding vapi file.

This tool is not a replacement for the wayland-scanner tool. It is intended to be used in conjunction with wayland-scanner to generate Vala bindings for Wayland protocols.

# wl-vala-gen

similar to wl-vapi-gen, wl-vapi-gen is a tool for generating Vala bindings for Wayland protocols, but this generates vala code which interacts with the wayland-client api directly without the need of generating the C stubs using wayland-scanner first.
Note wl-vala-gen requires some changes in teh wayland-client vala bindings, which are not upstreamed yet, until this gets merged, you need to vendor your own wayland-client.vapi file. More information on that can be found in the [vala merge request](https://gitlab.gnome.org/GNOME/vala/-/merge_requests/495).


Note that currently both tools can only create bindings for the client side of the protocol. The server side is not supported yet.
