# wl-vapi-gen

wl-vapi-gen is a tool for generating Vala bindings for Wayland protocols. After creating the C stubs for a wayland protocol using wayland-scanner, this tool can be used to generate the corresponding vapi file.

This tool is not a replacement for the wayland-scanner tool. It is intended to be used in conjunction with wayland-scanner to generate Vala bindings for Wayland protocols.

Note that currently this tool can only create bindings for the client side of the protocol. The server side is not supported yet.
