private void print_arg_type(OutputStream stream, int indent, Arg arg) {
  switch (arg.arg_type) {
    case OBJECT:
    case NEW_ID:
      if(arg.interface_name != null) {
        print(stream, 3, "&%s_interface,\n", arg.interface_name);
      }
      else {
        print(stream, 3, "null,\n");
      }
      break;
    default:
      print(stream, 3, "null,\n");
      break;
  }
}

private void write_request(OutputStream stream, Protocol protocol, Message request) {

    write_description(stream, 1, request.description);
    write_version(stream, 1, request.since, request.deprecated_since);

    Arg ret_type = null;
    string[] params = {};
    string[] req_params = {};
    Arg[] objects = {};
    foreach (var arg in request.args) {
      if (arg.arg_type == Arg.Type.NEW_ID){
        ret_type = arg;
        req_params += "null";
        continue;
      }
      if(arg.arg_type == Arg.Type.OBJECT && !arg.interface_name.has_prefix("wl_")) {
        objects += arg;
        req_params += @"$(arg.name)_proxy";
      }
      else {
        req_params += arg.name;
      }
      params += @"$(arg.as_vala_type()) $(arg.name)";
    }
    string args = req_params.length == 0 ? "" : ", " + string.joinv(", ", req_params);
    print(stream, 1, "public %s %s(%s)\n", ret_type == null ? "void" : ret_type.as_vala_type(), request.name, string.joinv(", ", params));
    print(stream, 2, "requires(this.proxy != null) {\n");
    foreach (var obj in objects) {
      print(stream, 2, "Wl.Proxy %s_proxy = %s.get_proxy();\n", obj.name, obj.name);
    }
    if(ret_type != null) {
      print(stream, 2, "Wl.Proxy id =\n");
    }
    print(stream, 2, "this.proxy->marshal_flags(%d, %s, this.proxy->get_version(), %d%s);\n",
      request.opcode,
      ret_type == null ? "null" : @"&$(snake_to_pascal(protocol.name))Data.$(ret_type.interface_name)_interface",
      request.is_destructor ? 1 : 0,
      args 
      );
    if(request.is_destructor) {
      print(stream, 2, "this.proxy = null;\n");
    }
    if(ret_type != null) {
      print(stream, 2, "return new %s((owned) id);\n", ret_type.as_vala_type());
    }
    print(stream, 1, "}\n\n");
}

private void write_event(OutputStream stream, Protocol protocol, Interface interface, Message event) {
    string[] args = {};
    string[] signal_args = {};
    string[] internal_args = {};
    Arg[] objects = {};
    Arg new_id = null;
    foreach(Arg arg in event.args) {
      args += @"$(arg.as_vala_type()) $(arg.name)";
      signal_args += arg.name;
      if(arg.arg_type == Arg.Type.NEW_ID) {
        internal_args += @"owned Wl.Proxy $(arg.name)_proxy";
        new_id = arg;
      }
      else if(arg.arg_type == Arg.Type.OBJECT) {
        internal_args += @"Wl.Proxy $(arg.name)_proxy";
        objects += arg;
      }
      else {
        internal_args += @"$(arg.as_vala_type()) $(arg.name)";
      }
    }

    write_description(stream, 1, event.description);
    write_version(stream, 1, event.since, event.deprecated_since);
    print(stream, 1, "public signal void %s(%s);\n", event.name, string.joinv(", ", args));
    print(stream, 1, "[CCode(has_target = false)]\n");
    print(stream, 1, "private delegate void %sListener%s(void* data, %s %s%s%s);\n", snake_to_pascal(interface.name), snake_to_pascal(event.name), snake_to_pascal(interface.name), interface.name, args.length == 0 ? "" : ", ", string.joinv(", ", internal_args));
    print(stream, 1, "private void handle_%s(%s %s%s%s){\n", event.name, snake_to_pascal(interface.name), interface.name, internal_args.length == 0 ? "" : ", ", string.joinv(", ", internal_args));
    if(new_id != null) {
      print(stream, 2, "%s %s = new %s((owned) %s_proxy);\n", new_id.as_vala_type(), new_id.name, new_id.as_vala_type(), new_id.name);
    }
    foreach (var obj in objects) {
      print(stream, 2, "%s %s = %s_proxy.get_user_data();\n", obj.as_vala_type(), obj.name, obj.name);
    }
    print(stream, 2, "this.%s(%s);\n", event.name, string.joinv(", ", signal_args));
    print(stream, 1, "}\n\n");
}

private void write_enum(OutputStream stream, Enum enum, Interface interface) {
  write_description(stream, 0, enum.description);
  write_version(stream, 0, enum.since);
  if(enum.bitfield) {
    print(stream, 0, "[Flags]\n");
  }
  print(stream, 0, "public enum %s%s {\n", snake_to_pascal(interface.name), snake_to_pascal(enum.name));
  enum.entries.@foreach(e => {
    write_description(stream, 1, e.description, e.summary);
    write_version(stream, 1, e.since, e.deprecated_since);
    print(stream, 1, "%s,\n", e.name.up());
    return true;
  });
  print(stream, 0, "}\n\n");
}


private void write_interface(OutputStream stream, Protocol protocol, Interface interface) {

  write_description(stream, 0, interface.description);

  print(stream, 0, "public class %s : Object {\n", snake_to_pascal(interface.name));
  print(stream, 1, "private Wl.Proxy* proxy;\n\n");

  print(stream, 1, "public unowned Wl.Proxy get_proxy() {\n");
  print(stream, 2, "return this.proxy;\n");
  print(stream, 1, "}\n\n");
  

  Message destructor = null;

  foreach (var request in interface.requests) {
    if(request.name == "destroy") destructor = request;
    else if (request.is_destructor && destructor == null) destructor = request;
    write_request(stream, protocol, request);
  }

  if(destructor == null) {
    print(stream, 1, "public void destroy() {\n");
    print(stream, 2, "this.proxy.destroy();\n");
    print(stream, 2, "this.proxy = null;\n");
    print(stream, 1, "}\n\n");
  }

  foreach (var event in interface.events) {
    write_event(stream, protocol, interface, event);
  }

  if(interface.events.size > 0) {
    print(stream, 1, "private struct %sListener {\n", snake_to_pascal(interface.name));
    foreach (var event in interface.events) {
      print(stream, 2, "public %sListener%s %s;\n", snake_to_pascal(interface.name), snake_to_pascal(event.name), event.name);
    }
    print(stream, 1, "}\n\n");

    print(stream, 1, "private %sListener listener = {\n", snake_to_pascal(interface.name));
    foreach (var event in interface.events) {
      print(stream, 2, "handle_%s,\n", event.name);
    }
    print(stream, 1, "};\n\n");
  }

  if(interface.is_global) {
    print(stream, 1, "public %s.bind(Wl.Registry registry, uint32 name) {\n", snake_to_pascal(interface.name));
    print(stream, 2, "%sData.init();\n", snake_to_pascal(protocol.name));
    print(stream, 2, "this.proxy =  registry.bind(name, ref %sData.%s_interface, %sData.%s_interface.version);\n", 
      snake_to_pascal(protocol.name),
      interface.name,
      snake_to_pascal(protocol.name),
      interface.name
    );
    print(stream, 2, "this.proxy->set_user_data(this);\n");
    if(interface.events.size > 0) {
      print(stream, 2, "this.proxy->add_listener((void*) &listener, this);\n");
    }
    print(stream, 1, "}\n\n");
  }

  print(stream, 1, "public %s(owned Wl.Proxy proxy) {\n", snake_to_pascal(interface.name));
  print(stream, 2, "%sData.init();\n", snake_to_pascal(protocol.name));
  print(stream, 2, "this.proxy = (owned) proxy;\n");
  print(stream, 2, "this.proxy->set_user_data(this);\n");
  if(interface.events.size > 0) {
    print(stream, 2, "this.proxy->add_listener((void*) &listener, this);\n");
  }
  print(stream, 1, "}\n\n");

  print(stream, 1, "~%s() {\n", snake_to_pascal(interface.name));
  print(stream, 2, "if(this.proxy != null)\n");
  print(stream, 3, "this.%s();\n", destructor == null ? "destroy" : destructor.name);
  print(stream, 1, "}\n\n");

  print(stream, 0, "}\n\n");

  interface.enums.foreach(e => { write_enum(stream, e, interface); return true;});
}

private void write_protocol(OutputStream stream, Protocol protocol) {
  print(stream, 0, "// Generated VALA file using wl-vala-gen %s\n\n", Config.VERSION);

  foreach (var interface in protocol.external_interfaces) {
    print(stream, 0, "[CCode(cheader_filename = \"wayland-client.h\", cname = \"%s_interface\")]\n", interface);
    print(stream, 0, "private extern Wl.Interface %s_interface;\n\n", interface);
  }

  write_description(stream, 0, protocol.description);
  print(stream, 0, "namespace %sData {\n", snake_to_pascal(protocol.name));

  foreach (var interface in protocol.interfaces) {
    print(stream, 1, "public static Wl.Interface %s_interface = {\n", interface.name);
    print(stream, 2, "\"%s\", %d,\n", interface.name, interface.version);
    print(stream, 2, "0, null,\n");
    print(stream, 2, "0, null\n");
    print(stream, 1, "};\n\n");

    print(stream, 1, "private static Wl.Message[] %s_requests;\n", interface.name);
    print(stream, 1, "private static Wl.Message[] %s_events;\n\n", interface.name);
  }

  print(stream, 1, "private static Wl.Interface*[] %s_types;\n\n", protocol.name);
  print(stream, 1, "private static bool initialized = false;\n\n");

  print(stream, 1, "private static void init() {\n");
  print(stream, 2, "if (initialized) return;\n");
  print(stream, 2, "initialized = true;\n\n");

  
  print(stream, 2, "%s_types = {\n", protocol.name);

  int type_index = 0;
  foreach (var interface in protocol.interfaces) {
    foreach (var message in interface.requests) {
      message.type_index = type_index;
      foreach (var arg in message.args) {
        print_arg_type(stream, 3, arg);
        type_index++;
      }
    }

    foreach (var message in interface.events) {
      message.type_index = type_index;
      foreach (var arg in message.args) {
        print_arg_type(stream, 3, arg);
        type_index++;
      }
    }
  }
  print(stream, 2, "};\n");

  foreach (var interface in protocol.interfaces) {
    if(interface.requests.size > 0) {
      print(stream, 2, "%s_requests = {\n", interface.name);
      foreach (var message in interface.requests) {
        print(stream, 3, "{ \"%s\", \"%s\", *(&%s_types + %d) },\n", message.name, message.get_signature(), protocol.name, message.type_index);
      }
      print(stream, 2, "};\n");
      print(stream, 2, "%s_interface.methods = %s_requests;\n\n", interface.name, interface.name);
    }

    if(interface.events.size > 0) {
      print(stream, 2, "%s_events = {\n", interface.name);
      foreach (var message in interface.events) {
        print(stream, 3, "{ \"%s\", \"%s\", *(&%s_types + %d) },\n", message.name, message.get_signature(), protocol.name, message.type_index);
      }
      print(stream, 2, "};\n");
      print(stream, 2, "%s_interface.events = %s_events;\n\n", interface.name, interface.name);
    }
  }

  print(stream, 1, "}\n");
 
  print(stream, 0, "}\n");

  foreach (var interface in protocol.interfaces) {
    write_interface(stream, protocol, interface);
  }


}

static bool version;
static string protocol_file;
static string vala;

const OptionEntry[] options = {
    { "version", 'v', OptionFlags.NONE, OptionArg.NONE, ref version, "Print version number", null },
    { "protocol", 'p', OptionFlags.NONE, OptionArg.FILENAME, ref protocol_file, "The wayland protocol to parse", null },
    { "vala", 'a', OptionFlags.NONE, OptionArg.FILENAME, ref vala, "The location of the output vala file", null },
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
	if(vala == null) {
	  printerr("error: required argument vala not specified.\n");
	  return 1;
	}

  Protocol protocol;
  try {
    protocol = parse_protocol(protocol_file);
  } catch (ParseError e) {
    critical("Failed to parse protocol: %s\n", e.message);
    return 1;
  }

  var file = File.new_for_path(vala);
  write_protocol(file.replace(null, false, 1, null), protocol);

  return 0;
}
