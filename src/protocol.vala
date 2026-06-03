using GLib;
using Gee;
using Xml;

public errordomain ParseError {
    UNKNOWN_VALUE,
    MISSING_ATTRIBUTE,
    INVALID_ATTRIBUTE,
    INVALID_ROOT,
    XML_ERROR
}

private static string? read_attr (Xml.TextReader reader, string name) {
    string? value = reader.get_attribute (name);
    return (value == null || value == "") ? null : value;
}

private static string read_required_attr (Xml.TextReader reader, string name) throws ParseError {
    string? value = read_attr (reader, name);
    if (value == null) {
        throw new ParseError.MISSING_ATTRIBUTE (
            "Element '%s' is missing required attribute '%s'".printf (reader.const_name (), name)
        );
    }
    return (!) value;
}

private static int int_attr (Xml.TextReader reader, string name, int default_value = 0) throws ParseError {
    string? value = read_attr (reader, name);
    if (value == null) {
        return default_value;
    }

  int result = 0;
    if (!int.try_parse (value, out result)) {
        throw new ParseError.INVALID_ATTRIBUTE (
            "Element '%s' has invalid integer attribute '%s'='%s'".printf (reader.const_name (), name, value)
        );
    }

    return result;
}

private static bool bool_attr (Xml.TextReader reader, string name, bool default_value = false) throws ParseError {
    string? value = read_attr (reader, name);
    if (value == null) {
        return default_value;
    }

    switch (value) {
        case "true":
            return true;
        case "false":
            return false;
        default:
            throw new ParseError.INVALID_ATTRIBUTE (
                "Element '%s' has invalid boolean attribute '%s'='%s'".printf (reader.const_name (), name, value)
            );
    }
}

public string snake_to_pascal (string name) {
    var builder = new StringBuilder ();

    foreach (string part in name.split ("_")) {
        if (part == "")
            continue;

        builder.append_unichar (part[0].toupper ());
        if (part.length > 1)
            builder.append (part.substring (1));
    }

    return builder.str;
}

string? collapse_whitespace (string? input) {
    if (input == null) {
        return null;
    }

    try {
        Regex re = new Regex ("\\s+");
        return re.replace (input, -1, 0, " ");
    } catch (RegexError e) {
        return input;
    }
}

private static string read_element_text (Xml.TextReader reader) throws ParseError {
    if (reader.is_empty_element () == 1) {
        return "";
    }

    int start_depth = reader.depth ();
    var builder = new StringBuilder ();

    while (reader.read () == 1) {
        switch (reader.node_type ()) {
            case Xml.ReaderType.TEXT:
            case Xml.ReaderType.CDATA:
            case Xml.ReaderType.SIGNIFICANT_WHITESPACE:
            case Xml.ReaderType.WHITESPACE:
                string? value = reader.const_value ();
                if (value != null) {
                    builder.append (value);
                }
                break;

            case Xml.ReaderType.END_ELEMENT:
                if (reader.depth () == start_depth) {
                    return builder.str;
                }
                break;

            default:
                break;
        }
    }

    throw new ParseError.XML_ERROR ("Unexpected end of XML while reading text content");
}

private static Description read_description (Xml.TextReader reader) throws ParseError {
    var description = new Description ();
    description.summary = read_attr (reader, "summary");
    description.description = read_element_text (reader);
    return description;
}

private static string read_copyright (Xml.TextReader reader) throws ParseError {
    return read_element_text (reader);
}

private static void skip_element (Xml.TextReader reader) throws ParseError {
    if (reader.is_empty_element () == 1) {
        return;
    }

    int start_depth = reader.depth ();
    while (reader.read () == 1) {
        if (reader.node_type () == Xml.ReaderType.END_ELEMENT && reader.depth () == start_depth) {
            return;
        }
    }

    throw new ParseError.XML_ERROR ("Unexpected end of XML while skipping element");
}

public class Protocol {
    public string name { get; internal set; }
    public string? copyright { get; internal set; }
    public Description? description { get; internal set; }
    public Gee.ArrayList<Interface> interfaces { get; internal set; }
    public Gee.HashSet<string> external_interfaces { get; internal set; }

    public Protocol () {
        this.interfaces = new Gee.ArrayList<Interface> ();
        this.external_interfaces = new Gee.HashSet<string> ();
    }
}

public class Description {
    public string? summary { get; internal set; }
    public string? description { get; internal set; }
}

public class Interface {
    public string name { get; internal set; }
    public Description? description { get; internal set; }
    public int version { get; internal set; }
    public Gee.ArrayList<Message> requests { get; internal set; }
    public Gee.ArrayList<Message> events { get; internal set; }
    public Gee.ArrayList<Enum> enums { get; internal set; }
    public int opcode { get; set; default = 0; }
    public bool is_global { get; set; default = true; }

    public Interface () {
        this.requests = new Gee.ArrayList<Message> ();
        this.events = new Gee.ArrayList<Message> ();
        this.enums = new Gee.ArrayList<Enum> ();
    }
}

public class Message {
    public string name { get; internal set; }
    public Description? description { get; internal set; }
    public Gee.ArrayList<Arg> args { get; internal set; }
    public int since { get; internal set; default = -1; }
    public int deprecated_since { get; internal set; default = -1; }
    public bool is_destructor { get; internal set; default = false; }
    public int type_index { get; set; default = 0; }
    public int opcode { get; set; default = -1; }

    public Message () {
        this.args = new Gee.ArrayList<Arg> ();
    }

    public string get_signature() {
        string sig = "";

        if(this.since > 0) sig += since.to_string();
        
        foreach (var arg in this.args) {
            if(arg.nullable) sig += "?";
            switch (arg.arg_type) {
                case INT:
                    sig += "i";
                    break;
                case FD:
                    sig += "h";
                    break;
                case UINT:
                    sig += "u";
                    break;
                case FIXED:
                    sig += "f";
                    break;
                case STRING:
                    sig += "s";
                    break;
                case ARRAY:
                    sig += "a";
                    break;
                case OBJECT:
                    sig += "o";
                    break;
                case NEW_ID:
                    sig += "n";
                    break;
            }
        }

        return sig;
    }
}

public class Arg {
    public string name { get; internal set; }
    public Type arg_type { get; internal set; }
    public bool nullable { get; internal set; default = false; }
    public string? interface_name { get; internal set; }
    public string? enum_name { get; internal set; }

    public enum Type {
        [Description (nick = "new_id")]
        NEW_ID,
        [Description (nick = "int")]
        INT,
        [Description (nick = "uint")]
        UINT,
        [Description (nick = "fixed")]
        FIXED,
        [Description (nick = "string")]
        STRING,
        [Description (nick = "object")]
        OBJECT,
        [Description (nick = "array")]
        ARRAY,
        [Description (nick = "fd")]
        FD;

        public static Type from_string (string type) throws ParseError {
            EnumValue? enum_value = ((EnumClass) typeof (Type).class_ref ()).get_value_by_nick (type);
            if (enum_value == null) {
                throw new ParseError.UNKNOWN_VALUE (
                    @"String $(type) is not a valid value for $(typeof(Type).name())"
                );
            }
            return enum_value.value;
        }
    }

    public string as_vala_type () {
        string vala_type;

        switch (this.arg_type) {
            case INT:
            case FD:
                vala_type = "int32";
                break;
            case UINT:
                vala_type = "uint32";
                break;
            case FIXED:
                vala_type = "Wl.fixed_t";
                break;
            case STRING:
                vala_type = "string";
                break;
            case ARRAY:
                vala_type = "Wl.Array";
                break;
            case OBJECT:
            case NEW_ID:
                if (this.interface_name == null) {
                    warning ("argument %s of type object/new_id does not specify interface name.", this.name);
                    vala_type = "void*";
                } else if (this.interface_name.has_prefix ("wl_")) {
                    vala_type = @"Wl.$(snake_to_pascal (this.interface_name.offset (3)))";
                } else {
                    vala_type = snake_to_pascal (this.interface_name);
                }
                break;
            default:
                vala_type = "void*";
                break;
        }

        if (this.enum_name != null && (this.arg_type == Type.INT || this.arg_type == Type.UINT)) {
            if (this.enum_name.contains (".")) {
                string flattened = this.enum_name.replace (".", "_");
                vala_type = snake_to_pascal (flattened);
            } else {
                vala_type = snake_to_pascal (this.enum_name);
            }
        }

        if (this.nullable && (this.arg_type == Type.OBJECT || this.arg_type == Type.STRING)) {
            vala_type += "?";
        }

        return vala_type;
    }
}

public class Enum {
    public string name { get; internal set; }
    public Description? description { get; internal set; }
    public bool bitfield { get; internal set; }
    public Gee.ArrayList<EnumEntry> entries { get; internal set; }
    public int since { get; internal set; default = -1; }

    public Enum () {
        this.entries = new Gee.ArrayList<EnumEntry> ();
    }
}

public class EnumEntry {
    public string name { get; internal set; }
    public int value { get; internal set; }
    public string? summary { get; internal set; }
    public Description? description { get; internal set; }
    public int since { get; internal set; default = -1; }
    public int deprecated_since { get; internal set; default = -1; }
}

public static Protocol parse_protocol (string file_name) throws ParseError {
    Xml.TextReader reader = new Xml.TextReader.filename (file_name);
    if (reader == null) {
        throw new ParseError.XML_ERROR (
            "File %s not found or permissions missing".printf (file_name)
        );
    }

    Protocol? protocol = null;
    Interface? current_interface = null;
    Message? current_message = null;
    Enum? current_enum = null;
    EnumEntry? current_entry = null;
    Set<string> new_id_interfaces = new HashSet<string> ();

    while (reader.read () == 1) {

        string name = reader.const_name ();

        if(reader.node_type () == Xml.ReaderType.ELEMENT) {
        switch (name) {
            case "protocol":
                if (protocol != null) {
                    throw new ParseError.INVALID_ROOT ("Multiple protocol elements found");
                }

                protocol = new Protocol ();
                protocol.name = read_required_attr (reader, "name");
                break;

            case "copyright":
                if (protocol == null) {
                    throw new ParseError.INVALID_ROOT ("copyright outside protocol");
                }
                protocol.copyright = read_copyright (reader);
                break;

            case "description":
                if (current_message != null) {
                    current_message.description = read_description (reader);
                } else if (current_entry != null) {
                    current_entry.description = read_description (reader);
                } else if (current_enum != null) {
                    current_enum.description = read_description (reader);
                } else if (current_interface != null) {
                    current_interface.description = read_description (reader);
                } else if (protocol != null) {
                    protocol.description = read_description (reader);
                } else {
                    throw new ParseError.INVALID_ROOT ("description outside protocol");
                }
                break;

            case "interface":
                if (protocol == null) {
                    throw new ParseError.INVALID_ROOT ("interface outside protocol");
                }

                current_interface = new Interface ();
                current_interface.name = read_required_attr (reader, "name");
                current_interface.version = int_attr (reader, "version");
                protocol.interfaces.add (current_interface);
                break;

            case "request":
            case "event":
                if (current_interface == null) {
                    throw new ParseError.INVALID_ROOT (
                        "%s outside interface".printf (name)
                    );
                }

                current_message = new Message ();
                current_message.name = read_required_attr (reader, "name");
                current_message.since = int_attr (reader, "since", -1);
                current_message.deprecated_since = int_attr (reader, "deprecated-since", -1);
                current_message.is_destructor = read_attr (reader, "type") == "destructor"
                    || current_message.name == "destroy";

                if (current_message.deprecated_since > 0 &&
                    current_message.deprecated_since <= current_message.since) {
                    warning ("deprecated-since is smaller than or equal to since for message %s",
                             current_message.name);
                }

                if (name == "request") {
                    current_message.opcode = current_interface.opcode++;
                    current_interface.requests.add (current_message);
                } else {
                    current_interface.events.add (current_message);
                }
                break;

            case "arg":
                if (current_message == null) {
                    throw new ParseError.INVALID_ROOT ("arg outside request/event");
                }

                var arg = new Arg ();
                arg.name = read_required_attr (reader, "name");
                arg.arg_type = Arg.Type.from_string (read_required_attr (reader, "type"));
                arg.nullable = bool_attr (reader, "allow-null", false);
                arg.interface_name = read_attr (reader, "interface");
                var enum_name = read_attr (reader, "enum");
                if (enum_name != null) {
                    if (enum_name.contains (".")) {
                        arg.enum_name = enum_name;
                    } else {
                        arg.enum_name = current_interface.name + "." + enum_name;
                    }
                }

                if (arg.nullable && arg.arg_type != Arg.Type.STRING && arg.arg_type != Arg.Type.OBJECT) {
                    warning ("argument '%s' of type %s can't be nullable",
                             arg.name, arg.arg_type.to_string ());
                }

                if(arg.arg_type == Arg.Type.NEW_ID) {
                    new_id_interfaces.add (arg.interface_name);
                }
                if(arg.interface_name != null && arg.interface_name.has_prefix ("wl_")) {
                    protocol.external_interfaces.add (arg.interface_name);
                }
                current_message.args.add (arg);
                break;

            case "enum":
                if (current_interface == null) {
                    throw new ParseError.INVALID_ROOT ("enum outside interface");
                }

                current_enum = new Enum ();
                current_enum.name = read_required_attr (reader, "name");
                current_enum.bitfield = bool_attr (reader, "bitfield", false);
                current_enum.since = int_attr (reader, "since", -1);
                current_interface.enums.add (current_enum);
                break;

            case "entry":
                if (current_enum == null) {
                    throw new ParseError.INVALID_ROOT ("entry outside enum");
                }

                current_entry = new EnumEntry ();
                current_entry.name = read_required_attr (reader, "name");
                current_entry.value = int_attr (reader, "value");
                current_entry.summary = collapse_whitespace (read_attr (reader, "summary"));
                current_entry.since = int_attr (reader, "since", -1);
                current_entry.deprecated_since = int_attr (reader, "deprecated-since", -1);

                if (current_entry.deprecated_since > 0 && current_entry.deprecated_since <= current_entry.since) {
                    warning ("deprecated-since is smaller than or equal to since for enum entry %s",
                             current_entry.name);
                }

                current_enum.entries.add (current_entry);
                break;

            default:
                warning ("ignoring unknown element %s.", name);
                skip_element (reader);
                break;
        }
        }

        if (reader.node_type() == Xml.ReaderType.END_ELEMENT || (reader.node_type () == Xml.ReaderType.ELEMENT && reader.is_empty_element () == 1)) {
            switch (name) {
                case "interface":
                    current_interface = null;
                    break;
                case "request":
                case "event":
                    current_message = null;
                    break;
                case "entry":
                    current_entry = null;
                    break;
                case "enum":
                    current_enum = null;
                    break;
                default:
                    break;
            }
        }
    }

    if (protocol == null) {
        throw new ParseError.INVALID_ROOT ("The root element is not a protocol");
    }

    foreach (var interface in protocol.interfaces) {
        if(new_id_interfaces.contains (interface.name)) {
            interface.is_global = false;
        }
    }

    return protocol;
}
