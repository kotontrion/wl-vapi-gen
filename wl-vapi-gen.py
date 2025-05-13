#!/usr/bin/env python3

import argparse
import xml.etree.ElementTree as ET

version = "@VERSION@"

BASE_TYPE_MAP = {
    "fixed": "Wl.fixed_t",
    "string": "string",
    "array": "Wl.Array",
    "fd": "int32",
    "int": "int32",
    "uint": "uint32",
}


def map_vala_type(type_name, interface, interface_attr=None, enum_attr=None):
    if type_name == "object" and interface_attr:
        if interface_attr.startswith("wl_"):
            return "Wl." + snake_to_pascal(interface_attr[3:])
        return map_vala_type(interface_attr, interface)

    if type_name == "new_id" and interface_attr:
        return map_vala_type(interface_attr, interface)

    if enum_attr and type_name in ("int", "uint"):
        if "." in enum_attr:
            enum_interface, enum_name = enum_attr.split(".")
            return f"{map_vala_type(enum_interface, enum_interface)}{snake_to_pascal(enum_name)}"
        return f"{map_vala_type(interface, interface)}{snake_to_pascal(enum_attr)}"

    return BASE_TYPE_MAP.get(type_name, snake_to_pascal(type_name))


def snake_to_pascal(name):
    return "".join(word.capitalize() for word in name.split("_"))


def snake_to_camel(name):
    parts = name.split("_")
    return parts[0] + "".join(word.capitalize() for word in parts[1:])


def snake_to_screaming_snake(name):
    return name.upper()


def generate_vapi_from_xml(protocol_file, output_vapi_file, cheader_filename):
    try:
        tree = ET.parse(protocol_file)
        root = tree.getroot()

        with open(output_vapi_file, "w") as f_vapi:
            f_vapi.write(f"// Generated VAPI file using wl-vapi-gen {version}\n\n")

            for interface in root.findall("interface"):
                interface_name_snake = interface.get("name")
                interface_name_vala = map_vala_type(
                    interface_name_snake, interface_name_snake
                )
                free_function = None

                for request in interface.findall("request"):
                    if (
                        request.get("destroyer") == "true"
                        or request.get("name") == "destroy"
                    ):
                        free_function = f"{interface_name_snake}_{request.get('name')}"
                        break

                annotation = f'[CCode (cheader_filename="{cheader_filename}", cname="struct {interface_name_snake}", cprefix="{interface_name_snake}_", free_function="{free_function}")]'

                f_vapi.write(
                    f"{annotation}\n[Compact]\npublic class {interface_name_vala} : Wl.Proxy {{\n"
                )

                f_vapi.write(
                    f'  [CCode (cname = "{interface_name_snake}_interface")]\n'
                )
                f_vapi.write("  public static Wl.Interface iface;\n\n")

                f_vapi.write("  public void set_user_data(void* user_data);\n")
                f_vapi.write("  public void* get_user_data();\n")
                f_vapi.write("  public uint32 get_version();\n\n")

                for request in interface.findall("request"):
                    request_name_snake = request.get("name")
                    request_name_vala = request_name_snake
                    params = []
                    return_type = "void"

                    for arg in request.findall("arg"):
                        arg_name = arg.get("name")
                        arg_type = arg.get("type")
                        arg_interface = arg.get("interface")
                        arg_enum = arg.get("enum")

                        if arg_type == "new_id":
                            return_type = map_vala_type(
                                arg_type,
                                interface_name_snake,
                                interface_attr=arg_interface,
                            )
                        else:
                            vala_type = map_vala_type(
                                arg_type,
                                interface_name_snake,
                                interface_attr=arg_interface,
                                enum_attr=arg_enum,
                            )
                            params.append(f"{vala_type} {arg_name}")

                    params_str = ", ".join(params)
                    if (
                        request.get("destroyer") == "true"
                        or request.get("name") == "destroy"
                    ):
                        f_vapi.write("  [DestroysInstance]\n")
                    f_vapi.write(
                        f"  public {return_type} {request_name_vala} ({params_str});\n"
                    )

                events = interface.findall("event")

                if events:
                    f_vapi.write(
                        f"  public int add_listener({interface_name_vala}Listener listener, void* data);\n"
                    )

                f_vapi.write("}\n\n")

                if events:
                    f_vapi.write(
                        f'\n[CCode (cname = "struct {interface_name_snake}_listener", has_type_id = false)]\n'
                    )
                    f_vapi.write(f"public struct {interface_name_vala}Listener {{\n")
                    for event in events:
                        event_name_snake = event.get("name")
                        event_name_vala = snake_to_camel(event_name_snake)
                        f_vapi.write(
                            f"  public {interface_name_vala}Listener{snake_to_pascal(event_name_snake)} {event_name_vala};\n"
                        )
                    f_vapi.write("}\n\n")

                    for event in events:
                        event_name_snake = event.get("name")
                        event_name_vala = snake_to_pascal(
                            event_name_snake
                        )  # Delegate name PascalCase
                        f_vapi.write(
                            "[CCode (has_target = false, has_typedef = false)]\n"
                        )
                        f_vapi.write(
                            f"public delegate void {interface_name_vala}Listener{event_name_vala}(void *data, {interface_name_vala} {interface_name_snake});\n\n"
                        )  # Delegate argument camelCase
                for enum in interface.findall("enum"):
                    enum_name_snake = enum.get("name")
                    enum_name_vala = snake_to_pascal(enum_name_snake)
                    f_vapi.write(
                        f'[CCode (cprefix="{snake_to_screaming_snake(interface_name_snake)}_{snake_to_screaming_snake(enum_name_snake)}_", cname="enum {interface_name_snake}_{enum_name_snake}", cheader_filename="{cheader_filename}")]\n'
                    )
                    if enum.get("bitfield") == "true":
                        f_vapi.write("[Flags]\n")
                    f_vapi.write(
                        f"public enum {interface_name_vala}{enum_name_vala} {{\n"
                    )
                    for entry in enum.findall("entry"):
                        enum_value = entry.get("name")
                        enum_value_vala = snake_to_screaming_snake(enum_value)
                        f_vapi.write(f"  {enum_value_vala},\n")
                    f_vapi.write("}\n\n")
                    f_vapi.flush()

    except FileNotFoundError:
        print(f"Error: Protocol file not found: {protocol_file}")
    except ET.ParseError as e:
        print(f"Error parsing XML: {e}")
    except Exception as e:
        print(f"An error occurred: {e}")


def main():
    parser = argparse.ArgumentParser(
        description="Generate VAPI files from Wayland protocol XML."
    )
    parser.add_argument(
        "--protocol", required=True, help="Path to the Wayland protocol XML file."
    )
    parser.add_argument("--vapi", required=True, help="Path to the output VAPI file.")
    parser.add_argument(
        "--cheader",
        required=True,
        help="The c header file name generated by wayland-scanner.",
    )
    args = parser.parse_args()

    generate_vapi_from_xml(args.protocol, args.vapi, args.cheader)


if __name__ == "__main__":
    main()
