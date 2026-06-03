private void write_request(OutputStream stream, int indent, Message request) {
  write_description(stream, indent, request.description);
  write_version(stream, indent, request.since, request.deprecated_since);
  if(request.is_destructor) {
    print(stream, indent, "[DestroysInstance]\n");
  }
  string return_type = "void";
  string[] args = {};
  foreach(Arg arg in request.args) {
    if(arg.arg_type == Arg.Type.NEW_ID) {
      return_type = arg.as_vala_type();
      continue;
    }
    args += @"$(arg.as_vala_type()) $(arg.name)";
  }
  print(stream, indent, "public %s %s(%s);\n", return_type, request.name, string.joinv(", ", args));
}

private void write_event(OutputStream stream, int indent, Message event, Interface interface) {
  write_description(stream, indent, event.description);
  write_version(stream, indent, event.since, event.deprecated_since);
  string[] args = {};
  foreach(Arg arg in event.args) {
    args += @"$(arg.as_vala_type()) $(arg.name)";
  }

  print(stream, indent, "[CCode (has_target=false, has_typedef=false)]\n");

  string params = args.length == 0 ? "" : ", " + string.joinv(", ", args);
  print(stream, indent, "public delegate void %sListener%s(void *data, %s %s%s);\n\n", snake_to_pascal(interface.name), snake_to_pascal(event.name), snake_to_pascal(interface.name), interface.name, params);
}

private void write_enum(OutputStream stream, int indent, Enum enum, Interface interface) {
  write_description(stream, indent, enum.description);
  write_version(stream, indent, enum.since);
  print(stream, 0, "[CCode (cprefix=\"%s_%s_\", cname=\"enum %s_%s\", cheader_filename=\"%s\")]\n", interface.name.up(), enum.name.up(), interface.name, enum.name, cheader);
  if(enum.bitfield) {
    print(stream, 0, "[Flags]\n");
  }
  print(stream, 0, "public enum %s%s {\n", snake_to_pascal(interface.name), snake_to_pascal(enum.name));
  enum.entries.@foreach(e => {
    write_description(stream, 1, e.description, e.summary);
    write_version(stream, indent, e.since, e.deprecated_since);
    print(stream, 1, "%s,\n", e.name.up());
    return true;
  });
  print(stream, 0, "}\n\n");
}

private void write_interface(OutputStream stream, Interface interface) {
  write_description(stream, 0, interface.description);
  
  string free_func = @"$(interface.name)_destroy";
  interface.requests.@foreach(r => { 
    if(r.is_destructor) {
      free_func = @"$(interface.name)_$(r.name)";
      return false;
    }
    return true;
  });
  
  print(stream, 0, "[CCode (cheader_filename=\"%s\", cname=\"%s\", cprefix=\"%s\", free_function=\"%s\")]\n",
    cheader,
    @"struct $(interface.name)",
    @"$(interface.name)_",
    free_func);
  print(stream, 0, "[Compact]\n");
  print(stream, 0, "public class %s : Wl.Proxy {\n", snake_to_pascal(interface.name));
  print(stream, 1, "[CCode(cname=\"%s_interface\")]\n", interface.name);
  print(stream, 1, "public static Wl.Interface iface;\n\n");

  print(stream, 1, "public void set_user_data(void* user_data);\n");
  print(stream, 1, "public void* get_user_data();\n");
  print(stream, 1, "public uint32 get_version();\n\n");

  interface.requests.@foreach(r => { write_request(stream, 1, r); return true; });
 
  if(interface.events.size > 0) {
    print(stream, 1, "public int add_listener(%sListener listener, void* data);\n", snake_to_pascal(interface.name));
  }

  print(stream, 0, "}\n\n");

  if(interface.events.size > 0) {
    print(stream, 0, "[CCode (cname=\"struct %s_listener\", has_type_id=false)]\n", interface.name);
    print(stream, 0, "public struct %sListener {\n", snake_to_pascal(interface.name));
    interface.events.@foreach(e => { print(stream, 1, "public %sListener%s %s;\n", snake_to_pascal(interface.name), snake_to_pascal(e.name), e.name); return true; });
    print(stream, 0, "}\n\n");
  }

  interface.events.@foreach(e => { write_event(stream, 0, e, interface); return true; });
  print(stream, 0, "\n");
  interface.enums.@foreach(e => { write_enum(stream, 0, e, interface); return true; });

}

private void write_protocol(OutputStream stream, Protocol protocol) {
  print(stream, 0, "// Generated VAPI file using wl-vapi-gen %s\n\n", Config.VERSION);

  protocol.interfaces.@foreach(i => { write_interface(stream, i); return true; });

}

static bool version;
static string protocol_file;
static string vapi;
static string cheader;

const OptionEntry[] options = {
    { "version", 'v', OptionFlags.NONE, OptionArg.NONE, ref version, "Print version number", null },
    { "protocol", 'p', OptionFlags.NONE, OptionArg.FILENAME, ref protocol_file, "The wayland protocol to parse", null },
    { "vapi", 'a', OptionFlags.NONE, OptionArg.FILENAME, ref vapi, "The location of the output vapi file", null },
    { "cheader", 'c', OptionFlags.NONE, OptionArg.FILENAME, ref cheader, "The c header file name", null },
    { null },
};

public static int main(string[] args) {

  try {
		var opt_context = new OptionContext ();
		opt_context.set_help_enabled (true);
		opt_context.add_main_entries (options, null);
		opt_context.parse (ref args);
	} catch (OptionError e) {
		printerr ("error: %s\n", e.message);
		printerr ("Run '%s --help' to see a full list of available command line options.\n", args[0]);
		return 1;
	}

	if(version) {
	  stdout.printf("%s\n", Config.VERSION);
	  return 0;
	}

	if(protocol_file == null) {
	  printerr("error: required argument protocol not specified.\n");
	  return 1;
	}
	if(vapi == null) {
	  printerr("error: required argument vapi not specified.\n");
	  return 1;
	}
	if(cheader == null) {
	  printerr("error: required argument cheader not specified.\n");
	  return 1;
	}


  Protocol protocol;
  try {
    protocol = parse_protocol(protocol_file);
  } catch (ParseError e) {
    critical("Failed to parse protocol: %s\n", e.message);
    return 1;
  }
  var file = File.new_for_path(vapi);
  write_protocol(file.replace(null, false, 1, null), protocol);
  

  return 0;
}
